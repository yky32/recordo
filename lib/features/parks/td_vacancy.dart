import 'dart:math' as math;

import 'package:recordo/features/parks/park.dart';

/// TD participating car parks — live vacancy overlay. Not catalog_dump.
class TdHourlyVacancy {
  const TdHourlyVacancy({
    required this.parkId,
    required this.nameTc,
    required this.lat,
    required this.lng,
    required this.vacancy,
    this.heightM,
    this.lastUpdate,
  });

  final String parkId;
  final String nameTc;
  final double lat;
  final double lng;

  /// `-1` no data, `0` full, `>0` empty bays (private car HOURLY).
  final int vacancy;
  final double? heightM;
  final String? lastUpdate;

  bool get hasData => vacancy >= 0;
  bool get isFull => vacancy == 0;
  bool get hasSpace => vacancy > 0;

  String get label {
    if (vacancy < 0) return '空位無數據';
    if (vacancy == 0) return '滿';
    return '有位 $vacancy';
  }

  Map<String, dynamic> toJson() => {
        'parkId': parkId,
        'nameTc': nameTc,
        'lat': lat,
        'lng': lng,
        'vacancy': vacancy,
        if (heightM != null) 'heightM': heightM,
        if (lastUpdate != null) 'lastUpdate': lastUpdate,
      };

  factory TdHourlyVacancy.fromJson(Map<String, dynamic> m) {
    return TdHourlyVacancy(
      parkId: '${m['parkId'] ?? ''}',
      nameTc: '${m['nameTc'] ?? ''}',
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      vacancy: (m['vacancy'] as num).toInt(),
      heightM: m['heightM'] == null ? null : (m['heightM'] as num).toDouble(),
      lastUpdate: m['lastUpdate'] as String?,
    );
  }
}

class TdBasicPark {
  const TdBasicPark({
    required this.parkId,
    required this.nameTc,
    required this.lat,
    required this.lng,
    this.heightM,
  });

  final String parkId;
  final String nameTc;
  final double lat;
  final double lng;
  final double? heightM;
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

int? hourlyPrivateVacancy(Map<String, dynamic> carPark) {
  final types = carPark['vehicle_type'];
  if (types is! List) return null;
  for (final t in types) {
    if (t is! Map) continue;
    if ('${t['type']}' != 'P') continue;
    final cats = t['service_category'];
    if (cats is! List) continue;
    for (final c in cats) {
      if (c is! Map) continue;
      if ('${c['category']}' != 'HOURLY') continue;
      final v = c['vacancy'];
      if (v is int) return v;
      return int.tryParse('$v');
    }
  }
  return null;
}

List<TdBasicPark> parseTdBasic(dynamic raw) {
  final root = raw is Map ? raw['car_park'] : raw;
  if (root is! List) return const [];
  final out = <TdBasicPark>[];
  for (final e in root) {
    if (e is! Map) continue;
    final lat = _num(e['latitude']);
    final lng = _num(e['longitude']);
    final id = '${e['park_id'] ?? ''}';
    if (id.isEmpty || lat == null || lng == null) continue;
    final h = _num(e['height']);
    out.add(
      TdBasicPark(
        parkId: id,
        nameTc: '${e['name_tc'] ?? e['name_en'] ?? id}',
        lat: lat,
        lng: lng,
        heightM: (h != null && h > 0) ? h : null,
      ),
    );
  }
  return out;
}

Map<String, int> parseTdVacancyMap(dynamic raw) {
  final root = raw is Map ? raw['car_park'] : raw;
  if (root is! List) return const {};
  final out = <String, int>{};
  for (final e in root) {
    if (e is! Map) continue;
    final id = '${e['park_id'] ?? ''}';
    if (id.isEmpty) continue;
    final v = hourlyPrivateVacancy(Map<String, dynamic>.from(e));
    if (v != null) out[id] = v;
  }
  return out;
}

List<TdHourlyVacancy> joinTdLive({
  required List<TdBasicPark> basic,
  required Map<String, int> vacancy,
}) {
  return [
    for (final b in basic)
      TdHourlyVacancy(
        parkId: b.parkId,
        nameTc: b.nameTc,
        lat: b.lat,
        lng: b.lng,
        vacancy: vacancy[b.parkId] ?? -1,
        heightM: b.heightM,
      ),
  ];
}

/// Slim pin for isolate match. Do not send full [Park] across isolates.
class TdParkPin {
  const TdParkPin({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.tdParkId = '',
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final String tdParkId;
}

double _meters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Isolate entry. Payload = `{parks: [{id,name,lat,lng,tdParkId}], live: [...]}`.
Map<String, dynamic> matchTdToParksIsolate(Map<String, dynamic> raw) {
  final parks = <TdParkPin>[];
  for (final e in (raw['parks'] as List)) {
    if (e is! Map) continue;
    parks.add(
      TdParkPin(
        id: '${e['id']}',
        name: '${e['name']}',
        lat: (e['lat'] as num).toDouble(),
        lng: (e['lng'] as num).toDouble(),
        tdParkId: '${e['tdParkId'] ?? ''}',
      ),
    );
  }
  final live = <TdHourlyVacancy>[];
  for (final e in (raw['live'] as List)) {
    if (e is! Map) continue;
    live.add(TdHourlyVacancy.fromJson(Map<String, dynamic>.from(e)));
  }
  final mapped = matchTdPinsToLive(parks: parks, live: live);
  return {for (final e in mapped.entries) e.key: e.value.toJson()};
}

Map<String, TdHourlyVacancy> matchTdToParks({
  required List<Park> parks,
  required List<TdHourlyVacancy> live,
  double maxMeters = 80,
}) {
  return matchTdPinsToLive(
    parks: [
      for (final p in parks)
        TdParkPin(
          id: p.id,
          name: p.name,
          lat: p.lat,
          lng: p.lng,
          tdParkId: p.tdParkId,
        ),
    ],
    live: live,
    maxMeters: maxMeters,
  );
}

/// Snap TD lots onto catalog parks.
/// 1) [Park.tdParkId] official join  2) distinctive name  3) ≤80m geo (grid).
/// Each TD lot claimed once. Never persist geo guesses from the client.
Map<String, TdHourlyVacancy> matchTdPinsToLive({
  required List<TdParkPin> parks,
  required List<TdHourlyVacancy> live,
  double maxMeters = 80,
}) {
  final liveById = <String, TdHourlyVacancy>{
    for (final t in live) t.parkId: t,
  };
  final claimed = <String>{};
  final out = <String, TdHourlyVacancy>{};

  for (final p in parks) {
    if (p.tdParkId.isEmpty) continue;
    final t = liveById[p.tdParkId];
    if (t == null || claimed.contains(t.parkId)) continue;
    claimed.add(t.parkId);
    out[p.id] = t;
  }

  final leftoverP = parks.where((p) => !out.containsKey(p.id)).toList();
  final leftoverT = live.where((t) => !claimed.contains(t.parkId)).toList();

  String norm(String s) => s
      .replaceAll('停車場', '')
      .replaceAll('泊車轉乘', '')
      .replaceAll(' ', '')
      .replaceAll('　', '')
      .trim();

  final byName = <String, TdHourlyVacancy>{};
  for (final t in leftoverT) {
    final n = norm(t.nameTc);
    if (n.length < 4) continue;
    if (byName.containsKey(n)) {
      byName.remove(n); // ambiguous
    } else {
      byName[n] = t;
    }
  }
  for (final p in leftoverP) {
    final n = norm(p.name);
    if (n.length < 4) continue;
    final t = byName[n];
    if (t == null || claimed.contains(t.parkId)) continue;
    claimed.add(t.parkId);
    out[p.id] = t;
  }

  const cell = 0.0012;
  String key(double lat, double lng) =>
      '${(lat / cell).round()},${(lng / cell).round()}';
  final grid = <String, List<TdHourlyVacancy>>{};
  for (final t in live) {
    if (claimed.contains(t.parkId)) continue;
    (grid[key(t.lat, t.lng)] ??= []).add(t);
  }

  for (final p in parks) {
    if (out.containsKey(p.id)) continue;
    TdHourlyVacancy? best;
    var bestD = maxMeters;
    final ci = (p.lat / cell).round();
    final cj = (p.lng / cell).round();
    for (var di = -1; di <= 1; di++) {
      for (var dj = -1; dj <= 1; dj++) {
        final bucket = grid['${ci + di},${cj + dj}'];
        if (bucket == null) continue;
        for (final t in bucket) {
          if (claimed.contains(t.parkId)) continue;
          final d = _meters(p.lat, p.lng, t.lat, t.lng);
          if (d <= bestD) {
            bestD = d;
            best = t;
          }
        }
      }
    }
    if (best != null) {
      claimed.add(best.parkId);
      out[p.id] = best;
    }
  }
  return out;
}
