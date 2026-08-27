import 'package:recordo/features/parks/park.dart';

/// Overlay only until the dump is as new or newer than this device's write.
bool overlayWins({DateTime? localTs, DateTime? dumpTs}) {
  if (localTs == null) return false;
  if (dumpTs == null) return true;
  return localTs.isAfter(dumpTs);
}

bool catalogNeedsPricePatch({
  required DateTime? localPricesAt,
  required DateTime? remotePricesAt,
}) {
  if (remotePricesAt == null) return false;
  if (localPricesAt == null) return true;
  return remotePricesAt.isAfter(localPricesAt);
}

/// Map leftover seed-id overlay keys onto OSM catalog ids (~90m).
String? remapLocalParkId({
  required String localId,
  required Park? seed,
  required List<Park> catalog,
}) {
  if (catalog.any((p) => p.id == localId)) return localId;
  if (seed == null) return null;
  var bestI = -1;
  var bestD = 1e18;
  const threshold = 90 * 90;
  for (var i = 0; i < catalog.length; i++) {
    final o = catalog[i];
    final dLat = (seed.lat - o.lat) * 111000;
    final dLng = (seed.lng - o.lng) * 111000 * 0.92;
    final d = dLat * dLat + dLng * dLng;
    if (d < bestD) {
      bestD = d;
      bestI = i;
    }
  }
  if (bestI >= 0 && bestD < threshold) return catalog[bestI].id;
  return null;
}
