import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/price_guard.dart';
import 'package:recordo/features/parks/supabase_park_remote.dart';

/// Parks = OSM skeleton + seed prices + local UGC + optional Supabase UGC.
class ParkRepository {
  ParkRepository({SupabaseParkRemote? remote})
      : _remote = remote ?? SupabaseParkRemote();

  final SupabaseParkRemote _remote;

  List<Park>? _osmCache;
  List<Park>? _mergedBase;
  Map<String, RemoteParkPrice> _remotePrices = {};
  List<Park> _remoteUgcParks = const [];

  Future<void> ensureLoaded() async {
    if (_mergedBase == null) {
      final osm = await _loadOsm();
      _mergedBase = _mergeSeedOverOsm(osm, hkSeedParks);
    }
    // Best-effort pull shared UGC
    try {
      final prices = await _remote.fetchPrices();
      final remoteParks = await _remote.fetchUgcParks();
      _remotePrices = prices;
      _remoteUgcParks = remoteParks;
    } catch (_) {}
  }

  /// Force refresh remote UGC (e.g. pull-to-refresh later).
  Future<void> refreshRemote() async {
    try {
      _remotePrices = await _remote.fetchPrices();
      _remoteUgcParks = await _remote.fetchUgcParks();
    } catch (_) {}
  }

  Future<List<Park>> _loadOsm() async {
    if (_osmCache != null) return _osmCache!;
    try {
      final raw =
          await rootBundle.loadString('assets/data/hk_osm_parks.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = (map['parks'] as List? ?? const []);
      _osmCache = list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return Park(
          id: m['id'] as String? ?? 'osm-unknown',
          name: m['name'] as String? ?? '停車場',
          district: m['district'] as String? ?? '香港',
          lat: (m['lat'] as num).toDouble(),
          lng: (m['lng'] as num).toDouble(),
          heightM: (m['heightM'] as num?)?.toDouble(),
          source: 'osm',
        );
      }).toList();
    } catch (_) {
      _osmCache = const [];
    }
    return _osmCache!;
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
    final remote = _remotePrices[p.id];

    double? hourly = p.hourlyHkd;
    double? daily = p.dailyHkd;
    double? night = p.nightHkd;
    var confirms = p.ugcConfirms;
    DateTime? updated = p.priceUpdatedAt;
    var source = p.source;
    var priceNote = p.priceNote;

    // Local wins if newer or only local
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

    // Remote fills gaps / older — prefer remote if newer than local
    if (remote != null) {
      final localTs = updated;
      final remoteTs = remote.updatedAt;
      final remoteNewer = remoteTs != null &&
          (localTs == null || remoteTs.isAfter(localTs));
      if (remoteNewer || localRaw is! Map) {
        hourly = remote.hourly ?? hourly;
        daily = remote.daily ?? daily;
        night = remote.night ?? night;
        if (remote.priceNote.isNotEmpty) priceNote = remote.priceNote;
        confirms = remote.confirms;
        updated = remote.updatedAt ?? updated;
        source = 'ugc-remote';
      } else {
        // still take higher confirm count
        if (remote.confirms > confirms) confirms = remote.confirms;
        if (priceNote.isEmpty && remote.priceNote.isNotEmpty) {
          priceNote = remote.priceNote;
        }
      }
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
    final base = _mergedBase ?? List<Park>.from(hkSeedParks);
    final localNews = _localUgcNewParks();
    final remoteIds = _remoteUgcParks.map((e) => e.id).toSet();
    final localOnly =
        localNews.where((p) => !remoteIds.contains(p.id)).toList();
    final combined = [...base, ..._remoteUgcParks, ...localOnly];
    // Dedupe by id (prefer first)
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

    // 1) Always local (offline OK)
    final map = Map<String, dynamic>.from(
      Bootstrap.store.getJsonMap(StorageKeys.ugcPrices) ?? {},
    );
    final existing = map[parkId] is Map
        ? Map<String, dynamic>.from(map[parkId] as Map)
        : <String, dynamic>{};
    final confirms = (existing['ugcConfirms'] as int? ?? 0) + 1;
    final noteOut = noteClamped != null
        ? noteClamped
        : (existing['priceNote'] as String? ?? '');
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

    // 2) Best-effort Supabase
    return _remote.insertPriceReport(
      parkId: parkId,
      hourly: h ?? (existing['hourlyHkd'] as num?)?.toDouble(),
      daily: d ?? (existing['dailyHkd'] as num?)?.toDouble(),
      night: n ?? (existing['nightHkd'] as num?)?.toDouble(),
      priceNote: noteOut.isEmpty ? null : noteOut,
      confirmOnly: confirmOnly,
    );
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

    await _remote.insertUgcPark(park, note: note, address: address);

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

  int get osmCount => _osmCache?.length ?? 0;
  int get baseCount => _mergedBase?.length ?? 0;
}
