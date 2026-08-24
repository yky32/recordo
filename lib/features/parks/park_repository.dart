import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/parks/park.dart';

/// Parks = OSM skeleton (bundled) + curated seed (prices) + local UGC.
/// Prices never come from OSM — UGC / seed only.
class ParkRepository {
  List<Park>? _osmCache;
  List<Park>? _mergedBase;

  Future<void> ensureLoaded() async {
    if (_mergedBase != null) return;
    final osm = await _loadOsm();
    _mergedBase = _mergeSeedOverOsm(osm, hkSeedParks);
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

  /// Prefer curated seed name/price when within ~90m of an OSM pin.
  List<Park> _mergeSeedOverOsm(List<Park> osm, List<Park> seeds) {
    final usedOsm = <int>{};
    final out = <Park>[];

    for (final s in seeds) {
      var bestI = -1;
      var bestD = 1e18;
      for (var i = 0; i < osm.length; i++) {
        if (usedOsm.contains(i)) continue;
        final o = osm[i];
        final d = _approxM(s.lat, s.lng, o.lat, o.lng);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }
      if (bestI >= 0 && bestD < 90 * 90) {
        usedOsm.add(bestI);
        final o = osm[bestI];
        // Keep OSM id for stable UGC later, but seed brand name + prices
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

  static double _approxM(double lat1, double lng1, double lat2, double lng2) {
    final dLat = (lat1 - lat2) * 111000;
    final dLng = (lng1 - lng2) * 111000 * 0.92; // HK ~22°
    return dLat * dLat + dLng * dLng; // compare squared; 90m²=8100
  }

  List<Park> _ugcNewParks() {
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

  /// Sync after [ensureLoaded]. Applies UGC price overlay.
  List<Park> allWithUgc() {
    final base = _mergedBase ?? List<Park>.from(hkSeedParks);
    final ugc = Bootstrap.store.getJsonMap(StorageKeys.ugcPrices) ?? {};
    final priced = base.map((p) {
      final raw = ugc[p.id];
      if (raw is! Map) return p;
      final m = Map<String, dynamic>.from(raw);
      return p.copyWith(
        hourlyHkd: (m['hourlyHkd'] as num?)?.toDouble() ?? p.hourlyHkd,
        dailyHkd: (m['dailyHkd'] as num?)?.toDouble() ?? p.dailyHkd,
        nightHkd: (m['nightHkd'] as num?)?.toDouble() ?? p.nightHkd,
        ugcConfirms: m['ugcConfirms'] as int? ?? p.ugcConfirms,
        priceUpdatedAt: m['priceUpdatedAt'] != null
            ? DateTime.tryParse(m['priceUpdatedAt'] as String)
            : p.priceUpdatedAt,
        source: p.source.startsWith('ugc') ? p.source : 'ugc',
      );
    });
    final news = _ugcNewParks().map((p) {
      final raw = ugc[p.id];
      if (raw is! Map) return p;
      final m = Map<String, dynamic>.from(raw);
      return p.copyWith(
        hourlyHkd: (m['hourlyHkd'] as num?)?.toDouble() ?? p.hourlyHkd,
        dailyHkd: (m['dailyHkd'] as num?)?.toDouble() ?? p.dailyHkd,
        nightHkd: (m['nightHkd'] as num?)?.toDouble() ?? p.nightHkd,
        ugcConfirms: m['ugcConfirms'] as int? ?? p.ugcConfirms,
        priceUpdatedAt: m['priceUpdatedAt'] != null
            ? DateTime.tryParse(m['priceUpdatedAt'] as String)
            : p.priceUpdatedAt,
        source: 'ugc-new',
      );
    });
    return [...priced, ...news];
  }

  Park? byId(String id) {
    try {
      return allWithUgc().firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> reportPrice({
    required String parkId,
    double? hourly,
    double? daily,
    double? night,
    bool confirmOnly = false,
  }) async {
    final map = Map<String, dynamic>.from(
      Bootstrap.store.getJsonMap(StorageKeys.ugcPrices) ?? {},
    );
    final existing = map[parkId] is Map
        ? Map<String, dynamic>.from(map[parkId] as Map)
        : <String, dynamic>{};
    final confirms = (existing['ugcConfirms'] as int? ?? 0) + 1;
    map[parkId] = {
      'hourlyHkd': hourly ?? existing['hourlyHkd'],
      'dailyHkd': daily ?? existing['dailyHkd'],
      'nightHkd': night ?? existing['nightHkd'],
      'ugcConfirms': confirms,
      'priceUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      'confirmOnly': confirmOnly,
    };
    await Bootstrap.store.setJson(StorageKeys.ugcPrices, map);
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
    final park = {
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
    list.insert(0, park);
    await Bootstrap.store.setJson(StorageKeys.ugcNewParks, list);

    if (hourly != null || daily != null || night != null) {
      await reportPrice(
        parkId: id,
        hourly: hourly,
        daily: daily,
        night: night,
      );
    }

    return byId(id)!;
  }

  int get osmCount => _osmCache?.length ?? 0;
  int get baseCount => _mergedBase?.length ?? 0;
}
