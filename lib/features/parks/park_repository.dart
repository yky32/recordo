import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/parks/park.dart';

/// Parks = seed list (Places-shaped). Prices overlay from local UGC.
class ParkRepository {
  List<Park> allWithUgc() {
    final ugc = Bootstrap.store.getJsonMap(StorageKeys.ugcPrices) ?? {};
    return hkSeedParks.map((p) {
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
    }).toList();
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
}
