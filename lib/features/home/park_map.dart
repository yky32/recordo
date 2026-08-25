import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/features/parks/park.dart';

/// Full-screen map. Parent overlays search/sheet.
/// [centerOn] places target on optical mid of [bandTopY]↔[bandBottomY].
class ParkMap extends StatefulWidget {
  const ParkMap({
    super.key,
    required this.parks,
    this.selectedId,
    this.bandTopY = 120,
    this.bandBottomY = 500,
    this.onSelect,
    this.onUserLocation,
    this.onPinMoved,
    this.onLocateState,
    this.onMapInteraction,
  });

  final List<Park> parks;
  final String? selectedId;
  final double bandTopY;
  final double bandBottomY;
  final ValueChanged<String>? onSelect;
  final ValueChanged<LatLng>? onUserLocation;
  final ValueChanged<LatLng>? onPinMoved;
  final void Function(bool locating, String? error)? onLocateState;
  final VoidCallback? onMapInteraction;

  @override
  State<ParkMap> createState() => ParkMapState();
}

class ParkMapState extends State<ParkMap> {
  static const hkCenter = LatLng(22.3193, 114.1694);

  final _map = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  bool _locating = false;
  bool _didInitialRecenter = false;
  bool _programmaticMove = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      locate(forceCamera: true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _map.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ParkMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedId != null &&
        widget.selectedId != oldWidget.selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) centerOnSelected();
      });
    }
  }

  void centerOnSelected() {
    final id = widget.selectedId;
    if (id == null) return;
    final p = widget.parks.where((e) => e.id == id).firstOrNull;
    if (p == null) return;
    _centerOn(LatLng(p.lat, p.lng), zoom: 15.5);
  }

  /// Place [ll] in the upper part of search↔sheet band (not mid —
  /// mid sits on the sheet lip and "almost blocks" the pin).
  void _centerOn(LatLng ll, {double? zoom}) {
    if (!mounted) return;
    final z = (zoom ?? 15.5).clamp(14.0, 16.5);
    final h = MediaQuery.sizeOf(context).height;

    var top = widget.bandTopY;
    var bottom = widget.bandBottomY;
    if (!top.isFinite || !bottom.isFinite || bottom <= top + 60) {
      top = h * 0.14;
      bottom = h * 0.55;
    }
    // ~30% down the visible band → clear of sheet top + CTA
    final targetY = top + (bottom - top) * 0.30;
    // flutter_map: +offset.y moves point DOWN on screen
    final offsetY = targetY - h / 2;

    _programmaticMove = true;
    try {
      final cam = _map.camera;
      final newPoint = cam.projectAtZoom(ll, z);
      final center = cam.unprojectAtZoom(newPoint - Offset(0, offsetY), z);
      if (!_map.move(center, z)) {
        _map.move(ll, z, offset: Offset(0, offsetY));
      }
    } catch (_) {
      try {
        _map.move(ll, z, offset: Offset(0, offsetY));
      } catch (_) {
        try {
          _map.move(ll, z);
        } catch (_) {}
      }
    }
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      _programmaticMove = false;
    });
  }

  void centerOnMe({bool animated = true}) {
    final me = _me;
    if (me == null) {
      locate(forceCamera: true);
      return;
    }
    _centerOn(me, zoom: 15.5);
  }

  Future<void> locate({bool forceCamera = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    widget.onLocateState?.call(true, null);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        widget.onLocateState?.call(false, '請開定位服務');
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        widget.onLocateState?.call(false, '未有定位權限');
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        widget.onLocateState?.call(false, '請去設定開定位');
        return;
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
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        widget.onLocateState?.call(false, '定位失敗 · 再試');
        return;
      }

      final hk = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        hkCenter.latitude,
        hkCenter.longitude,
      );
      if (hk > 500000) {
        pos = Position(
          longitude: 114.1747,
          latitude: 22.2783,
          timestamp: DateTime.now(),
          accuracy: 10,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      }

      _applyPosition(pos, moveCamera: forceCamera || !_didInitialRecenter);
      widget.onLocateState?.call(false, null);

      await _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen(
        (p) {
          final d = Geolocator.distanceBetween(
            p.latitude,
            p.longitude,
            hkCenter.latitude,
            hkCenter.longitude,
          );
          if (d > 500000) return;
          _applyPosition(p, moveCamera: false);
        },
        onError: (_) {},
      );
    } catch (_) {
      widget.onLocateState?.call(false, '定位失敗 · 再試');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _applyPosition(Position pos, {required bool moveCamera}) {
    final ll = LatLng(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() => _me = ll);
    widget.onUserLocation?.call(ll);
    if (moveCamera) {
      _didInitialRecenter = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerOn(ll, zoom: 15.5);
      });
    }
  }

  void _onMapEvent(MapEvent e) {
    if (e is MapEventMoveStart ||
        e is MapEventTap ||
        e is MapEventLongPress ||
        e is MapEventSecondaryTap) {
      widget.onMapInteraction?.call();
    }
    if (_programmaticMove) return;
    if (e is MapEventMoveEnd) {
      widget.onPinMoved?.call(_map.camera.center);
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      for (final p in widget.parks)
        Marker(
          point: LatLng(p.lat, p.lng),
          width: p.id == widget.selectedId ? 52 : 36,
          height: p.id == widget.selectedId ? 52 : 36,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => widget.onSelect?.call(p.id),
            child: _ParkPin(selected: p.id == widget.selectedId),
          ),
        ),
      if (_me != null)
        Marker(
          point: _me!,
          width: 22,
          height: 22,
          child: const _MeDot(),
        ),
    ];

    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final tileUrl = UberColors.mapTileUrl;
        return FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _me ?? hkCenter,
            initialZoom: 14.5,
            minZoom: 10,
            maxZoom: 18,
            backgroundColor: UberColors.mapBlock,
            onMapEvent: _onMapEvent,
            onTap: (tapPosition, point) => widget.onMapInteraction?.call(),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              key: ValueKey(tileUrl),
              // No {r} — retina @2x broke some CDN paths on device
              urlTemplate: tileUrl,
              fallbackUrl:
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.recordo',
              retinaMode: false,
              maxNativeZoom: 19,
              errorTileCallback: (tile, error, stackTrace) {
                if (kDebugMode) {
                  debugPrint('Tile error ${tile.coordinates}: $error');
                }
              },
            ),
            MarkerLayer(markers: markers),
          ],
        );
      },
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2F80ED),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F80ED).withValues(alpha: 0.45),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _ParkPin extends StatelessWidget {
  const _ParkPin({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = selected ? 46.0 : 32.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: selected ? UberColors.accent : UberColors.elevated2,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? UberColors.white
              : UberColors.white.withValues(alpha: 0.35),
          width: selected ? 3 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: UberColors.accent.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.local_parking_rounded,
        size: selected ? 24 : 16,
        color: selected ? UberColors.black : UberColors.white,
      ),
    );
  }
}

extension<E> on Iterable<E> {
  E? get firstOrNull {
    final i = iterator;
    if (!i.moveNext()) return null;
    return i.current;
  }
}
