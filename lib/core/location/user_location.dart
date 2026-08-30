import 'package:geolocator/geolocator.dart';

/// Result of a one-shot user location lookup.
class UserLocationResult {
  const UserLocationResult({this.lat, this.lng, this.error, this.demo = false});

  final double? lat;
  final double? lng;
  final String? error;
  /// Sim / 境外 — not a real HK GPS fix. Must not steal the camera.
  final bool demo;

  bool get ok => lat != null && lng != null;
}

/// Shared Geolocator lookup for map + report-park flows.
abstract final class UserLocationResolver {
  static const _hkLat = 22.2783;
  static const _hkLng = 114.1747;
  static const _maxKmFromHk = 500.0;

  static Future<UserLocationResult> resolve({
    bool requestPermission = true,
  }) async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return const UserLocationResult(error: '請開定位服務');
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && requestPermission) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        return const UserLocationResult(error: '未有定位權限');
      }
      if (perm == LocationPermission.deniedForever) {
        return const UserLocationResult(error: '請去設定開定位');
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        // Do not use lastKnown — stale 灣仔 cache flies the camera.
        pos = null;
      }
      if (pos == null) {
        return const UserLocationResult(error: '定位失敗 · 再試');
      }
      if (pos.latitude.abs() < 0.01 && pos.longitude.abs() < 0.01) {
        return const UserLocationResult(error: '定位無效');
      }

      final kmFromHk = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            _hkLat,
            _hkLng,
          ) /
          1000;
      if (kmFromHk > _maxKmFromHk) {
        // Simulator abroad: keep HK map, but do not pretend GPS is 灣仔.
        return const UserLocationResult(
          lat: _hkLat,
          lng: _hkLng,
          demo: true,
        );
      }
      return UserLocationResult(lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return const UserLocationResult(error: '定位失敗 · 再試');
    }
  }
}
