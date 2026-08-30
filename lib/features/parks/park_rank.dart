import 'package:geolocator/geolocator.dart';
import 'package:recordo/core/config/hk_wedge.dart';
import 'package:recordo/features/parks/park.dart';

/// Display rank tier — lower sorts first.
int parkDisplayTier(Park p) {
  if (p.isVerifiedPrice) return 0;
  if (p.hasPrice && p.hasUgcReports) return 1;
  if (p.hasPrice) return 2;
  return 3;
}

bool isWedgeLot(Park p) => HkWedge.containsPark(p);

int compareParksForDisplay(
  Park a,
  Park b, {
  required double? centerLat,
  required double? centerLng,
  bool preferWedge = true,
}) {
  // 「附近」= 距離。Wedge 只喺未有定位（冷啟動 CWB demo）先用。
  if (centerLat != null && centerLng != null) {
    final da = Geolocator.distanceBetween(centerLat, centerLng, a.lat, a.lng);
    final db = Geolocator.distanceBetween(centerLat, centerLng, b.lat, b.lng);
    final cmp = da.compareTo(db);
    if (cmp != 0) return cmp;
  } else if (preferWedge) {
    final aw = isWedgeLot(a) ? 0 : 1;
    final bw = isWedgeLot(b) ? 0 : 1;
    if (aw != bw) return aw.compareTo(bw);
  }

  final ta = parkDisplayTier(a);
  final tb = parkDisplayTier(b);
  if (ta != tb) return ta.compareTo(tb);

  final an = a.name == '停車場' ? 1 : 0;
  final bn = b.name == '停車場' ? 1 : 0;
  if (an != bn) return an.compareTo(bn);

  return a.name.compareTo(b.name);
}

/// One geodesic per park, then sort. Do not call [compareParksForDisplay]
/// with a center (that recomputes distance on every comparison).
List<Park> sortParksForDisplay(
  List<Park> list, {
  required double? centerLat,
  required double? centerLng,
  bool preferWedge = true,
}) {
  if (centerLat != null && centerLng != null) {
    final scored = <({Park p, double d})>[
      for (final p in list)
        (
          p: p,
          d: Geolocator.distanceBetween(centerLat, centerLng, p.lat, p.lng),
        ),
    ];
    scored.sort((a, b) {
      final byD = a.d.compareTo(b.d);
      if (byD != 0) return byD;
      return compareParksForDisplay(
        a.p,
        b.p,
        centerLat: null,
        centerLng: null,
        preferWedge: false,
      );
    });
    return [for (final e in scored) e.p];
  }
  final copy = List<Park>.from(list)
    ..sort(
      (a, b) => compareParksForDisplay(
        a,
        b,
        centerLat: null,
        centerLng: null,
        preferWedge: preferWedge,
      ),
    );
  return copy;
}

/// Split pipeline output for home sheet: featured vs collapsed remainder.
({List<Park> featured, List<Park> rest}) splitFeaturedRest(
  List<Park> sorted, {
  required bool searching,
}) {
  if (searching || sorted.isEmpty) {
    return (featured: sorted, rest: const []);
  }

  final featured = <Park>[];
  final rest = <Park>[];
  for (final p in sorted) {
    if (parkDisplayTier(p) <= 2) {
      featured.add(p);
    } else {
      rest.add(p);
    }
  }

  if (featured.isEmpty && sorted.isNotEmpty) {
    final take = sorted.length.clamp(0, 12);
    return (
      featured: sorted.sublist(0, take),
      rest: sorted.sublist(take),
    );
  }

  return (featured: featured, rest: rest);
}

/// Map pin select: selected lot always leads the featured list, even if it
/// sat outside the nearby window or was collapsed into [rest].
({List<Park> featured, List<Park> rest}) pinSelectedToFront({
  required List<Park> featured,
  required List<Park> rest,
  required String? selectedId,
  Park? fallback,
}) {
  if (selectedId == null || selectedId.isEmpty) {
    return (featured: featured, rest: rest);
  }
  Park? picked;
  final nextFeatured = <Park>[];
  for (final p in featured) {
    if (p.id == selectedId) {
      picked = p;
    } else {
      nextFeatured.add(p);
    }
  }
  final nextRest = <Park>[];
  for (final p in rest) {
    if (p.id == selectedId) {
      picked = p;
    } else {
      nextRest.add(p);
    }
  }
  picked ??= fallback;
  if (picked == null || picked.id != selectedId) {
    return (featured: featured, rest: rest);
  }
  return (featured: [picked, ...nextFeatured], rest: nextRest);
}
