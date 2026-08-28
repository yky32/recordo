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
  if (preferWedge) {
    final aw = isWedgeLot(a) ? 0 : 1;
    final bw = isWedgeLot(b) ? 0 : 1;
    if (aw != bw) return aw.compareTo(bw);
  }

  final ta = parkDisplayTier(a);
  final tb = parkDisplayTier(b);
  if (ta != tb) return ta.compareTo(tb);

  if (centerLat != null && centerLng != null) {
    final da = Geolocator.distanceBetween(centerLat, centerLng, a.lat, a.lng);
    final db = Geolocator.distanceBetween(centerLat, centerLng, b.lat, b.lng);
    final cmp = da.compareTo(db);
    if (cmp != 0) return cmp;
  }

  final an = a.name == '停車場' ? 1 : 0;
  final bn = b.name == '停車場' ? 1 : 0;
  if (an != bn) return an.compareTo(bn);

  return a.name.compareTo(b.name);
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
    if (parkDisplayTier(p) <= 2 && isWedgeLot(p)) {
      featured.add(p);
    } else if (parkDisplayTier(p) <= 1) {
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
