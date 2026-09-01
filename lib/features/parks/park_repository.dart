import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/parks/catalog_cache.dart';
import 'package:recordo/features/parks/community_paid_session.dart';
import 'package:recordo/features/parks/hk_districts.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_tariff.dart';
import 'package:recordo/features/parks/price_guard.dart';
import 'package:recordo/features/parks/price_verification.dart';
import 'package:recordo/features/parks/supabase_park_remote.dart';
import 'package:recordo/features/parks/sync_outbox.dart';
import 'package:recordo/features/parks/sync_rules.dart';
import 'package:recordo/features/parks/meter_street.dart';
import 'package:recordo/features/parks/meter_space.dart';

export 'package:recordo/features/parks/catalog_cache.dart' show CatalogSyncResult;

/// Parks = local catalog snapshot (cloud dump) + local UGC overlay.
/// Bundled OSM is first-run / offline fallback only.
class ParkRepository {
  ParkRepository({
    SupabaseParkRemote? remote,
    CatalogCache? cache,
    SyncOutbox? outbox,
  })  : _remote = remote ?? SupabaseParkRemote(),
        _cache = cache ?? CatalogCache(),
        _outbox = outbox ?? SyncOutbox();

  final SupabaseParkRemote _remote;
  final CatalogCache _cache;
  final SyncOutbox _outbox;

  List<Park>? _catalog;
  List<Park>? _ugcView;
  Map<String, Park>? _byId;
  int _catalogVersion = 0;
  DateTime? _pricesUpdatedAt;
  bool _fromCloud = false;

  int get catalogVersion => _catalogVersion;
  bool get playingFromCloudSnapshot => _fromCloud;

  Future<List<MeterStreet>> fetchMetersDump() => _remote.fetchMetersDump();

  Future<List<MeterSpace>> fetchMeterSpacesInBbox({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) =>
      _remote.fetchMeterSpacesInBbox(
        minLat: minLat,
        minLng: minLng,
        maxLat: maxLat,
        maxLng: maxLng,
      );
  void _invalidateUgcView() {
    _ugcView = null;
    _byId = null;
  }

  void _setCatalog(List<Park> parks) {
    _catalog = parks;
    _invalidateUgcView();
  }

  int get osmCount => _catalog?.length ?? 0;
  int get baseCount => _catalog?.length ?? 0;

  /// Instant: disk snapshot, else bundled OSM+seed.
  Future<void> loadLocalFirst() async {
    if (_catalog != null && _catalog!.isNotEmpty) return;
    final snap = await _cache.read();
    if (snap != null && snap.parks.isNotEmpty) {
      _setCatalog(snap.parks);
      _catalogVersion = snap.version;
      _pricesUpdatedAt = snap.pricesUpdatedAt;
      _fromCloud = snap.version > 0;
      return;
    }
    _setCatalog(await _loadBundledFallback());
    _catalogVersion = 0;
    _fromCloud = false;
  }

  Future<void> ensureLoaded() async {
    await loadLocalFirst();
    await syncIfRemoteNewer();
  }

  /// Tiny version check; full dump only when the park list changed.
  /// Price-only updates patch rows via `prices_updated_at`.
  Future<CatalogSyncResult> syncIfRemoteNewer({bool force = false}) async {
    try {
      final meta = await _remote.fetchCatalogMeta();
      if (meta == null) {
        await _outbox.flush(_remote);
        return CatalogSyncResult.offline;
      }
      final localCount = _catalog?.length ?? 0;
      final needDump = force ||
          catalogNeedsDump(
            localVersion: _catalogVersion,
            remoteVersion: meta.version,
            localCount: localCount,
          );
      if (needDump) {
        final dump = await _remote.fetchCatalogDump();
        if (dump == null || dump.parks.isEmpty) {
          await _outbox.flush(_remote);
          return localCount > 0
              ? CatalogSyncResult.unchanged
              : CatalogSyncResult.offline;
        }
        _setCatalog(dump.parks);
        _catalogVersion = dump.version == 0 ? meta.version : dump.version;
        _pricesUpdatedAt = meta.pricesUpdatedAt ?? dump.pricesUpdatedAt;
        _fromCloud = true;
        await _persistSnapshot();
        await _remapAndPruneOverlay();
        await _outbox.flush(_remote);
        return CatalogSyncResult.updated;
      }

      if (catalogNeedsPricePatch(
        localPricesAt: _pricesUpdatedAt,
        remotePricesAt: meta.pricesUpdatedAt,
      )) {
        final patch = await _remote.fetchPricePatch(since: _pricesUpdatedAt);
        if (patch.isNotEmpty) {
          _mergePricePatch(patch);
        }
        _pricesUpdatedAt = meta.pricesUpdatedAt;
        await _persistSnapshot();
        await _remapAndPruneOverlay();
        await _outbox.flush(_remote);
        return patch.isEmpty
            ? CatalogSyncResult.unchanged
            : CatalogSyncResult.updated;
      }

      await _outbox.flush(_remote);
      return CatalogSyncResult.unchanged;
    } catch (_) {
      return CatalogSyncResult.offline;
    }
  }

  Future<void> _persistSnapshot() async {
    final parks = _catalog ?? const <Park>[];
    await _cache.write(
      CatalogDump(
        version: _catalogVersion,
        parks: parks,
        parkCount: parks.length,
        pricesUpdatedAt: _pricesUpdatedAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  PriceVerificationStatus _mergeVerification(Park old, Park incoming) {
    if (old.priceVerificationStatus == PriceVerificationStatus.verified) {
      return PriceVerificationStatus.verified;
    }
    return incoming.priceVerificationStatus;
  }

  void _mergePricePatch(List<Park> patch) {
    final byId = {for (final p in _catalog ?? const <Park>[]) p.id: p};
    for (final n in patch) {
      final old = byId[n.id];
      if (old == null) {
        byId[n.id] = n;
        continue;
      }
      byId[n.id] = old.copyWith(
        hourlyHkd: n.hourlyHkd,
        dailyHkd: n.dailyHkd,
        nightHkd: n.nightHkd,
        ugcConfirms: n.ugcConfirms,
        priceUpdatedAt: n.priceUpdatedAt,
        priceNote: n.priceNote,
        source: n.source,
        priceVerificationStatus: _mergeVerification(old, n),
        priceVerifiedAt: n.priceVerifiedAt ?? old.priceVerifiedAt,
        priceProvenance: n.priceProvenance != PriceProvenance.unknown
            ? n.priceProvenance
            : old.priceProvenance,
      );
    }
    _setCatalog(byId.values.toList());
  }

  Future<void> _remapAndPruneOverlay() async {
    final catalog = _catalog ?? const <Park>[];
    final byId = {for (final p in catalog) p.id: p};
    final seeds = {for (final s in hkSeedParks) s.id: s};
    final map = Map<String, dynamic>.from(
      Bootstrap.store.getJsonMap(StorageKeys.ugcPrices) ?? {},
    );
    if (map.isEmpty) return;
    final next = <String, dynamic>{};
    for (final e in map.entries) {
      if (e.value is! Map) continue;
      final local = Map<String, dynamic>.from(e.value as Map);
      final id = remapLocalParkId(
            localId: e.key,
            seed: seeds[e.key],
            catalog: catalog,
          ) ??
          e.key;
      final dumpPark = byId[id];
      if (dumpPark != null) {
        final localTs = DateTime.tryParse('${local['priceUpdatedAt'] ?? ''}');
        if (!overlayWins(localTs: localTs, dumpTs: dumpPark.priceUpdatedAt)) {
          continue;
        }
      }
      next[id] = local;
    }
    await Bootstrap.store.setJson(StorageKeys.ugcPrices, next);
    _invalidateUgcView();
  }

  Future<void> refreshRemote() async {
    await syncIfRemoteNewer();
    await _outbox.flush(_remote);
  }

  Future<int> flushOutbox() => _outbox.flush(_remote);

  int get pendingSyncCount => _outbox.pendingCount;

  Future<List<Park>> _loadBundledFallback() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/hk_osm_parks.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = (map['parks'] as List? ?? const []);
      final osm = list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return Park(
          id: m['id'] as String? ?? 'osm-unknown',
          name: prettyParkName(m['name'] as String? ?? '停車場'),
          district: m['district'] as String? ?? '香港',
          lat: (m['lat'] as num).toDouble(),
          lng: (m['lng'] as num).toDouble(),
          heightM: (m['heightM'] as num?)?.toDouble(),
          source: 'osm',
        );
      }).toList();
      return _mergeSeedOverOsm(osm, hkSeedParks);
    } catch (_) {
      return List<Park>.from(hkSeedParks);
    }
  }

  List<Park> _mergeSeedOverOsm(List<Park> osm, List<Park> seeds) {
    final usedOsm = <int>{};
    final out = <Park>[];

    for (final s in seeds) {
      var bestI = -1;
      var bestD = 1e18;
      for (var i = 0; i < osm.length; i++) {
        if (usedOsm.contains(i)) continue;
        final o = osm[i];
        final d = _approxM2(s.lat, s.lng, o.lat, o.lng);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }
      if (bestI >= 0 && bestD < 90 * 90) {
        usedOsm.add(bestI);
        final o = osm[bestI];
        out.add(
          Park(
            id: o.id,
            name: s.name,
            district: s.district,
            lat: o.lat,
            lng: o.lng,
            hourlyHkd: s.hourlyHkd,
            dailyHkd: s.dailyHkd,
            nightHkd: s.nightHkd,
            heightM: s.heightM ?? o.heightM,
            source: 'seed+osm',
            priceProvenance: s.priceProvenance,
            priceVerificationStatus: s.priceVerificationStatus,
            priceVerifiedAt: s.priceVerifiedAt,
            priceNote: s.priceNote,
          ),
        );
      } else {
        out.add(s);
      }
    }

    for (var i = 0; i < osm.length; i++) {
      if (!usedOsm.contains(i)) out.add(osm[i]);
    }
    return out;
  }

  static double _approxM2(double lat1, double lng1, double lat2, double lng2) {
    final dLat = (lat1 - lat2) * 111000;
    final dLng = (lng1 - lng2) * 111000 * 0.92;
    return dLat * dLat + dLng * dLng;
  }

  List<Park> _localUgcNewParks() {
    final list = Bootstrap.store.getJsonList(StorageKeys.ugcNewParks);
    return list.map((m) {
      return Park(
        id: m['id'] as String? ?? 'ugc-${m.hashCode}',
        name: m['name'] as String? ?? '未命名',
        district: m['district'] as String? ?? '香港',
        lat: (m['lat'] as num?)?.toDouble() ?? 22.3,
        lng: (m['lng'] as num?)?.toDouble() ?? 114.17,
        hourlyHkd: (m['hourlyHkd'] as num?)?.toDouble(),
        dailyHkd: (m['dailyHkd'] as num?)?.toDouble(),
        nightHkd: (m['nightHkd'] as num?)?.toDouble(),
        heightM: (m['heightM'] as num?)?.toDouble(),
        ugcConfirms: m['ugcConfirms'] as int? ?? 1,
        priceUpdatedAt: m['priceUpdatedAt'] != null
            ? DateTime.tryParse(m['priceUpdatedAt'] as String)
            : DateTime.now(),
        source: 'ugc-new',
      );
    }).toList();
  }

  Park _applyPrices(Park p) {
    final local = Bootstrap.store.getJsonMap(StorageKeys.ugcPrices);
    final localRaw = local?[p.id];

    double? hourly = p.hourlyHkd;
    double? daily = p.dailyHkd;
    double? night = p.nightHkd;
    var confirms = p.ugcConfirms;
    DateTime? updated = p.priceUpdatedAt;
    var source = p.source;
    var priceNote = p.priceNote;
    var verification = p.priceVerificationStatus;
    var verifiedAt = p.priceVerifiedAt;
    var provenance = p.priceProvenance;
    var tariff = p.tariff;

    if (p.isOperatorOfficial) {
      return p;
    }

    var name = p.name;
    var district = p.district;
    final ident = Bootstrap.store.getJsonMap(StorageKeys.ugcIdentity);
    final identRaw = ident?[p.id];
    if (identRaw is Map) {
      final im = Map<String, dynamic>.from(identRaw);
      final n = '${im['name'] ?? ''}'.trim();
      final d = '${im['district'] ?? ''}'.trim();
      if (n.length >= 2) name = n;
      if (d.length >= 2) district = d;
    }

    if (localRaw is Map) {
      final m = Map<String, dynamic>.from(localRaw);
      final localTs = m['priceUpdatedAt'] != null
          ? DateTime.tryParse(m['priceUpdatedAt'] as String)
          : null;
      if (overlayWins(localTs: localTs, dumpTs: p.priceUpdatedAt)) {
        hourly = PriceGuard.clampHourly(
              (m['hourlyHkd'] as num?)?.toDouble()) ??
            hourly;
        daily =
            PriceGuard.clampDaily((m['dailyHkd'] as num?)?.toDouble()) ?? daily;
        night =
            PriceGuard.clampNight((m['nightHkd'] as num?)?.toDouble()) ?? night;
        confirms = m['ugcConfirms'] as int? ?? confirms;
        updated = localTs ?? updated;
        final n = m['priceNote'] as String?;
        if (n != null && n.trim().isNotEmpty) priceNote = n.trim();
        source = p.source.startsWith('ugc') ? p.source : 'ugc';
        provenance = PriceProvenance.ugc;
        if (verification != PriceVerificationStatus.verified) {
          verification = PriceVerificationStatus.unverified;
        }
        final localTariff = ParkTariff.tryParse(m['tariff']);
        if (localTariff != null) tariff = localTariff;
      }
    }

    return p.copyWith(
      name: name,
      district: district,
      hourlyHkd: hourly,
      dailyHkd: daily,
      nightHkd: night,
      ugcConfirms: confirms,
      priceUpdatedAt: updated,
      source: source,
      priceNote: priceNote,
      priceVerificationStatus: verification,
      priceVerifiedAt: verifiedAt,
      priceProvenance: provenance,
      tariff: tariff,
    );
  }

  List<Park> allWithUgc() {
    if (_ugcView != null) return _ugcView!;
    final base = _catalog ?? List<Park>.from(hkSeedParks);
    final localNews = _localUgcNewParks();
    final ids = base.map((e) => e.id).toSet();
    final localOnly = localNews.where((p) => !ids.contains(p.id)).toList();
    final combined = [...base, ...localOnly];
    final seen = <String>{};
    final unique = <Park>[];
    for (final p in combined) {
      if (seen.add(p.id)) unique.add(p);
    }
    _ugcView = unique.map(_applyPrices).toList();
    _byId = {for (final p in _ugcView!) p.id: p};
    return _ugcView!;
  }

  Park? byId(String id) {
    _byId ??= {for (final p in allWithUgc()) p.id: p};
    return _byId![id];
  }

  /// Returns true if shared to Supabase (false = local only / offline / no key).
  /// Throws [ArgumentError] with message if out of [PriceGuard] range.
  Future<bool> reportPrice({
    required String parkId,
    double? hourly,
    double? daily,
    double? night,
    String? priceNote,
    bool confirmOnly = false,
    int? unitMinutes,
    double? unitAmount,
    double? offpeakAmount,
    ParkTariff? tariff,
  }) async {
    final err = PriceGuard.validateReport(
      hourly: hourly,
      daily: daily,
      night: night,
      note: priceNote,
      confirmOnly: confirmOnly,
      unitMinutes: unitMinutes,
      unitAmount: unitAmount,
    );
    if (err != null) {
      throw ArgumentError(err);
    }

    final h = PriceGuard.clampHourly(hourly);
    final d = PriceGuard.clampDaily(daily);
    final n = PriceGuard.clampNight(night);
    final noteClamped = priceNote != null
        ? PriceGuard.clampNote(priceNote)
        : null;

    final map = Map<String, dynamic>.from(
      Bootstrap.store.getJsonMap(StorageKeys.ugcPrices) ?? {},
    );
    final existing = map[parkId] is Map
        ? Map<String, dynamic>.from(map[parkId] as Map)
        : <String, dynamic>{};
    final confirms = (existing['ugcConfirms'] as int? ?? 0) + 1;
    final noteOut = noteClamped ?? (existing['priceNote'] as String? ?? '');
    map[parkId] = {
      'hourlyHkd': h ?? existing['hourlyHkd'],
      'dailyHkd': d ?? existing['dailyHkd'],
      'nightHkd': n ?? existing['nightHkd'],
      'priceNote': noteOut,
      'ugcConfirms': confirms,
      'priceUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      'confirmOnly': confirmOnly,
      'tariff': ?tariff?.toJson(),
      'unitMinutes': ?unitMinutes,
      'unitAmount': ?unitAmount,
    };
    await Bootstrap.store.setJson(StorageKeys.ugcPrices, map);
    _invalidateUgcView();

    final hourlyOut = h ?? (existing['hourlyHkd'] as num?)?.toDouble();
    final dailyOut = d ?? (existing['dailyHkd'] as num?)?.toDouble();
    final nightOut = n ?? (existing['nightHkd'] as num?)?.toDouble();
    final jobId = 'price-$parkId-${DateTime.now().millisecondsSinceEpoch}';
    await _outbox.enqueue(
      SyncJob(
        id: jobId,
        type: 'price',
        createdAt: DateTime.now().toUtc(),
        payload: {
          'parkId': parkId,
          'hourly': hourlyOut,
          'daily': dailyOut,
          'night': nightOut,
          'priceNote': noteOut.isEmpty ? null : noteOut,
          'confirmOnly': confirmOnly,
          'unitMinutes': ?unitMinutes,
          'unitAmount': ?unitAmount,
          'offpeakAmount': ?offpeakAmount,
        },
      ),
    );
    await _outbox.flush(_remote);
    return !_outbox.read().any((j) => j.id == jobId);
  }

  /// Fix OSM junk name / district. Official parks refused.
  Future<bool> reportIdentity({
    required String parkId,
    required String name,
    required String district,
  }) async {
    final p = byId(parkId);
    if (p == null) throw ArgumentError('找不到呢個場');
    if (!p.canEditIdentity) throw ArgumentError('官方場唔可以改名');
    final n = clampParkName(name);
    final d = clampDistrict(district);
    if (n == null) throw ArgumentError('名稱要 2–40 字');
    if (d == null) throw ArgumentError('請揀地區');

    final map = Map<String, dynamic>.from(
      Bootstrap.store.getJsonMap(StorageKeys.ugcIdentity) ?? {},
    );
    map[parkId] = {
      'name': n,
      'district': d,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await Bootstrap.store.setJson(StorageKeys.ugcIdentity, map);
    _invalidateUgcView();

    final jobId = 'ident-$parkId-${DateTime.now().millisecondsSinceEpoch}';
    await _outbox.enqueue(
      SyncJob(
        id: jobId,
        type: 'identity',
        createdAt: DateTime.now().toUtc(),
        payload: {'parkId': parkId, 'name': n, 'district': d},
      ),
    );
    await _outbox.flush(_remote);
    return !_outbox.read().any((j) => j.id == jobId);
  }

  /// Share a real payment (amount + duration). Never writes hourly median.
  Future<bool> reportPaidSession({
    required String parkId,
    required double amountHkd,
    required int durationMinutes,
  }) async {
    if (parkId.trim().isEmpty) {
      throw ArgumentError('缺少場 ID');
    }
    if (amountHkd <= 0 || amountHkd >= 10000) {
      throw ArgumentError('實付金額無效');
    }
    if (durationMinutes < 0 || durationMinutes >= 10080) {
      throw ArgumentError('泊車時長無效');
    }

    final jobId = 'paid-$parkId-${DateTime.now().millisecondsSinceEpoch}';
    await _outbox.enqueue(
      SyncJob(
        id: jobId,
        type: 'paid',
        createdAt: DateTime.now().toUtc(),
        payload: {
          'parkId': parkId,
          'amountHkd': amountHkd,
          'durationMinutes': durationMinutes,
        },
      ),
    );
    await _outbox.flush(_remote);
    return !_outbox.read().any((j) => j.id == jobId);
  }

  Future<List<CommunityPaidSession>> fetchCommunityPaidSessions(
    String parkId, {
    int limit = 8,
  }) {
    return _remote.fetchPaidSessions(parkId, limit: limit);
  }

  Future<Park> reportNewPark({
    required String name,
    required String district,
    String address = '',
    double? lat,
    double? lng,
    double? hourly,
    double? daily,
    double? night,
    double? heightM,
    String note = '',
  }) async {
    final id =
        'ugc-${DateTime.now().millisecondsSinceEpoch}-${name.hashCode.abs()}';
    final parkMap = {
      'id': id,
      'name': name,
      'district': district,
      'address': address,
      'lat': lat ?? 22.3193,
      'lng': lng ?? 114.1694,
      'hourlyHkd': hourly,
      'dailyHkd': daily,
      'nightHkd': night,
      'heightM': heightM,
      'note': note,
      'ugcConfirms': 1,
      'priceUpdatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final list = Bootstrap.store.getJsonList(StorageKeys.ugcNewParks);
    list.insert(0, parkMap);
    await Bootstrap.store.setJson(StorageKeys.ugcNewParks, list);
    _invalidateUgcView();

    final park = Park(
      id: id,
      name: name,
      district: district,
      lat: (parkMap['lat'] as num).toDouble(),
      lng: (parkMap['lng'] as num).toDouble(),
      hourlyHkd: hourly,
      dailyHkd: daily,
      nightHkd: night,
      heightM: heightM,
      ugcConfirms: 1,
      priceUpdatedAt: DateTime.now(),
      source: 'ugc-new',
    );

    await _outbox.enqueue(
      SyncJob(
        id: 'park-$id',
        type: 'park',
        createdAt: DateTime.now().toUtc(),
        payload: {
          'id': id,
          'name': name,
          'district': district,
          'address': address,
          'lat': park.lat,
          'lng': park.lng,
          'heightM': heightM,
          'note': note,
        },
      ),
    );
    await _outbox.flush(_remote);

    if (hourly != null || daily != null || night != null) {
      await reportPrice(
        parkId: id,
        hourly: hourly,
        daily: daily,
        night: night,
      );
    }

    return byId(id) ?? park;
  }
}
