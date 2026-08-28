import 'package:recordo/features/parks/park.dart';

/// Launch wedge: Causeway Bay + Tsim Sha Tsui (Phase A).
abstract final class HkWedge {
  static const districts = {'銅鑼灣', '尖沙咀'};

  /// Approx bbox covering CWB + TST cores.
  static const minLat = 22.272;
  static const maxLat = 22.302;
  static const minLng = 114.162;
  static const maxLng = 114.192;

  /// Curated seed ids in the wedge — expand toward 50 via gate verification.
  static const seedIds = {
    'ts_causeway',
    'lee_garden_1',
    'lee_garden_3',
    'vp_cwb',
    'hysan_place',
    'world_trade',
    'hc_tst',
    'k11_musea',
    'i_square',
    'k11_art',
    'china_hk_city',
  };

  static bool containsPark(Park p) {
    if (districts.contains(p.district)) return true;
    if (seedIds.contains(p.id)) return true;
    return p.lat >= minLat &&
        p.lat <= maxLat &&
        p.lng >= minLng &&
        p.lng <= maxLng;
  }

  static bool containsCoords(double lat, double lng) {
    return lat >= minLat &&
        lat <= maxLat &&
        lng >= minLng &&
        lng <= maxLng;
  }
}
