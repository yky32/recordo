import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/parks/park.dart';

/// Parks = seed list + local UGC new parks. Prices overlay from local UGC.
class ParkRepository {
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

  List<Park> allWithUgc() {
    final ugc = Bootstrap.store.getJsonMap(StorageKeys.ugcPrices) ?? {};
    final seeds = hkSeedParks.map((p) {
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
        source: 'ugc',
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
    return [...seeds, ...news];
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
}
