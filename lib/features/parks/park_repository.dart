import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/parks/catalog_cache.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/price_guard.dart';
import 'package:recordo/features/parks/supabase_park_remote.dart';
import 'package:recordo/features/parks/sync_outbox.dart';

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
  int _catalogVersion = 0;
  bool _fromCloud = false;

  int get catalogVersion => _catalogVersion;
  bool get playingFromCloudSnapshot => _fromCloud;
  int get osmCount => _catalog?.length ?? 0;
  int get baseCount => _catalog?.length ?? 0;

  /// Instant: disk snapshot, else bundled OSM+seed.
  Future<void> loadLocalFirst() async {
    if (_catalog != null && _catalog!.isNotEmpty) return;
    final snap = await _cache.read();
    if (snap != null && snap.parks.isNotEmpty) {
      _catalog = snap.parks;
      _catalogVersion = snap.version;
      _fromCloud = snap.version > 0;
      return;
    }
    _catalog = await _loadBundledFallback();
    _catalogVersion = 0;
    _fromCloud = false;
  }

  Future<void> ensureLoaded() async {
    await loadLocalFirst();
    await syncIfRemoteNewer();
  }

  /// Tiny version check; one dump only when cloud is newer (or empty local).
  Future<CatalogSyncResult> syncIfRemoteNewer({bool force = false}) async {
    try {
      final remoteVer = await _remote.fetchCatalogVersion();
      if (remoteVer == null) return CatalogSyncResult.offline;
      final localCount = _catalog?.length ?? 0;
      final need = force ||
          catalogNeedsDump(
            localVersion: _catalogVersion,
            remoteVersion: remoteVer,
            localCount: localCount,
          );
      if (!need) {
        await _outbox.flush(_remote);
        return CatalogSyncResult.unchanged;
      }

      final dump = await _remote.fetchCatalogDump();
      if (dump == null || dump.parks.isEmpty) {
        await _outbox.flush(_remote);
        return localCount > 0
            ? CatalogSyncResult.unchanged
            : CatalogSyncResult.offline;
      }
      _catalog = dump.parks;
      _catalogVersion = dump.version == 0 ? remoteVer : dump.version;
      _fromCloud = true;
      await _cache.write(
        CatalogDump(
          version: _catalogVersion,
          parks: dump.parks,
          parkCount: dump.parks.length,
          updatedAt: dump.updatedAt ?? DateTime.now().toUtc(),
        ),
      );
      await _outbox.flush(_remote);
      return CatalogSyncResult.updated;
    } catch (_) {
      return CatalogSyncResult.offline;
    }
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
            ugcConfirms: s.ugcConfirms,
            priceUpdatedAt: s.priceUpdatedAt,
            source: 'seed+osm',
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

    if (localRaw is Map) {
      final m = Map<String, dynamic>.from(localRaw);
      hourly = PriceGuard.clampHourly(
            (m['hourlyHkd'] as num?)?.toDouble()) ??
          hourly;
      daily =
          PriceGuard.clampDaily((m['dailyHkd'] as num?)?.toDouble()) ?? daily;
      night =
          PriceGuard.clampNight((m['nightHkd'] as num?)?.toDouble()) ?? night;
      confirms = m['ugcConfirms'] as int? ?? confirms;
      updated = m['priceUpdatedAt'] != null
          ? DateTime.tryParse(m['priceUpdatedAt'] as String) ?? updated
          : updated;
      final n = m['priceNote'] as String?;
      if (n != null && n.trim().isNotEmpty) priceNote = n.trim();
      source = p.source.startsWith('ugc') ? p.source : 'ugc';
    }

    return p.copyWith(
      hourlyHkd: hourly,
      dailyHkd: daily,
      nightHkd: night,
      ugcConfirms: confirms,
      priceUpdatedAt: updated,
      source: source,
      priceNote: priceNote,
    );
  }

  List<Park> allWithUgc() {
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
    return unique.map(_applyPrices).toList();
  }

  Park? byId(String id) {
    try {
      return allWithUgc().firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
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
  }) async {
    final err = PriceGuard.validateReport(
      hourly: hourly,
      daily: daily,
      night: night,
      note: priceNote,
      confirmOnly: confirmOnly,
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
    };
    await Bootstrap.store.setJson(StorageKeys.ugcPrices, map);

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
        },
      ),
    );
    await _outbox.flush(_remote);
    return !_outbox.read().any((j) => j.id == jobId);
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
