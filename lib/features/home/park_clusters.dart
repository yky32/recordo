import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/features/parks/park.dart';

class ParkCluster {
  const ParkCluster({required this.parks, required this.center});

  final List<Park> parks;
  final LatLng center;

  bool get isSingle => parks.length == 1;
  Park get primary => parks.first;
}

/// Screen-space clustering. Priced pins stay as chips (高德); unnamed lots
/// collapse into counts unless they sit on a priced marker.
List<ParkCluster> clusterParks({
  required List<Park> parks,
  required Offset Function(LatLng) toScreen,
  required double radiusPx,
  String? keepSeparateId,
}) {
  if (parks.isEmpty) return const [];

  bool keep(Park p) =>
      p.isVerifiedPrice ||
      (p.hasPrice && p.hasUgcReports) ||
      p.id == keepSeparateId;
  final featured = parks.where(keep).toList();
  final rest = parks.where((p) => !keep(p)).toList();

  final featuredClusters = _greedy(
    featured,
    toScreen,
    radiusPx * 0.55,
    keepSeparateId,
  );

  if (rest.isEmpty) return featuredClusters;

  final r2 = radiusPx * radiusPx;
  final hidden = <String>{};
  if (radiusPx > 0) {
    final featuredPts = [
      for (final p in featured) toScreen(LatLng(p.lat, p.lng)),
    ];
    for (final p in rest) {
      final pt = toScreen(LatLng(p.lat, p.lng));
      for (final f in featuredPts) {
        final dx = pt.dx - f.dx;
        final dy = pt.dy - f.dy;
        if (dx * dx + dy * dy <= r2) {
          hidden.add(p.id);
          break;
        }
      }
    }
  }

  final leftover = rest.where((p) => !hidden.contains(p.id)).toList();
  final restClusters = _greedy(leftover, toScreen, radiusPx, null);
  return [...restClusters, ...featuredClusters];
}

List<ParkCluster> _greedy(
  List<Park> parks,
  Offset Function(LatLng) toScreen,
  double radiusPx,
  String? keepSeparateId,
) {
  if (parks.isEmpty) return const [];
  if (radiusPx <= 0) {
    return [
      for (final p in parks)
        ParkCluster(parks: [p], center: LatLng(p.lat, p.lng)),
    ];
  }

  final r2 = radiusPx * radiusPx;
  final used = <String>{};
  final out = <ParkCluster>[];

  for (final seed in parks) {
    if (!used.add(seed.id)) continue;
    if (seed.id == keepSeparateId) {
      out.add(ParkCluster(parks: [seed], center: LatLng(seed.lat, seed.lng)));
      continue;
    }
    final origin = toScreen(LatLng(seed.lat, seed.lng));
    final members = <Park>[seed];
    for (final other in parks) {
      if (used.contains(other.id) || other.id == keepSeparateId) continue;
      final p = toScreen(LatLng(other.lat, other.lng));
      final dx = p.dx - origin.dx;
      final dy = p.dy - origin.dy;
      if (dx * dx + dy * dy <= r2) {
        used.add(other.id);
        members.add(other);
      }
    }
    out.add(ParkCluster(parks: members, center: _centerOf(members)));
  }
  return out;
}

double clusterRadiusPx(double zoom) {
  if (zoom >= 17.6) return 12;
  if (zoom >= 16.8) return 20;
  if (zoom >= 16.0) return 28;
  if (zoom >= 15.2) return 38;
  if (zoom >= 14.2) return 52;
  if (zoom >= 13.0) return 68;
  return 84;
}

String pinPriceLabel(Park p) {
  if (p.hourlyHkd != null) return '\$${p.hourlyHkd!.toStringAsFixed(0)}';
  if (p.dailyHkd != null) return '\$${p.dailyHkd!.toStringAsFixed(0)}日';
  if (p.nightHkd != null) return '夜\$${p.nightHkd!.toStringAsFixed(0)}';
  return '';
}

LatLng _centerOf(List<Park> parks) {
  if (parks.length == 1) return LatLng(parks.first.lat, parks.first.lng);
  final priced = parks.where((p) => p.hasPrice).toList();
  final src = priced.isNotEmpty ? priced : parks;
  var lat = 0.0, lng = 0.0;
  for (final p in src) {
    lat += p.lat;
    lng += p.lng;
  }
  return LatLng(lat / src.length, lng / src.length);
}

double approxM2(LatLng a, LatLng b) {
  final dLat = (a.latitude - b.latitude) * 111000;
  final dLng = (a.longitude - b.longitude) * 111000 * 0.92;
  return dLat * dLat + dLng * dLng;
}

double clusterSpanM(ParkCluster c) {
  if (c.parks.length < 2) return 0;
  var maxD = 0.0;
  final a = LatLng(c.parks.first.lat, c.parks.first.lng);
  for (var i = 1; i < c.parks.length; i++) {
    final d = approxM2(a, LatLng(c.parks[i].lat, c.parks[i].lng));
    if (d > maxD) maxD = d;
  }
  return math.sqrt(maxD);
}
