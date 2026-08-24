import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park.dart';

/// Dark map + park markers + GPS. Locate control lives in HomeMapScreen.
class ParkMap extends StatefulWidget {
  const ParkMap({
    super.key,
    required this.parks,
    this.selectedId,
    this.onSelect,
    this.onUserLocation,
    this.onPinMoved,
    this.onLocateState,
    this.onMapInteraction,
    /// Screen Y of search bar bottom (top red line).
    this.bandTopY = 120,
    /// Screen Y of sheet top / handle (bottom red line).
    this.bandBottomY = 500,
  });

  final List<Park> parks;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final ValueChanged<LatLng>? onUserLocation;
  final ValueChanged<LatLng>? onPinMoved;
  final void Function(bool locating, String? error)? onLocateState;
  final VoidCallback? onMapInteraction;
  final double bandTopY;
  final double bandBottomY;

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
  double? _pendingBandTop;
  double? _pendingBandBottom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => locate(forceCamera: true));
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
    // Only re-center when selection changes — never on sheet drag.
    if (widget.selectedId != null &&
        widget.selectedId != oldWidget.selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) centerOnSelected(animated: true);
      });
    }
  }

  void centerOnSelected({bool animated = true}) {
    final id = widget.selectedId;
    if (id == null) return;
    final p = widget.parks.where((e) => e.id == id).firstOrNull;
    if (p == null) return;
    _centerOn(LatLng(p.lat, p.lng), zoom: 15.5);
  }

  /// Place [ll] at the exact midpoint of [bandTop]→[bandBottom] (red lines).
  /// Uses flutter_map moveRaw offset math only (CameraFit was wrong when sheet tall).
  void _centerOn(
    LatLng ll, {
    double? zoom,
    double? bandTop,
    double? bandBottom,
  }) {
    if (!mounted) return;
    final z = (zoom ?? 15.5).clamp(14.0, 16.5);
    final h = MediaQuery.sizeOf(context).height;

    var top = bandTop ?? widget.bandTopY;
    var bottom = bandBottom ?? widget.bandBottomY;
    if (!top.isFinite || !bottom.isFinite || bottom <= top + 60) {
      top = h * 0.14;
      bottom = h * 0.55;
    }

    // True midpoint between the two red lines
    final midY = (top + bottom) / 2.0;
    // flutter_map: offset +Y places the LatLng LOWER on screen.
    // Want LatLng at midY; geometric center is h/2 → offset.y = midY - h/2
    final offsetY = midY - h / 2;

    _programmaticMove = true;
    try {
      final cam = _map.camera;
      final newPoint = cam.projectAtZoom(ll, z);
      // Same as MapControllerImpl.moveRaw with offset
      final center = cam.unprojectAtZoom(
        newPoint - Offset(0, offsetY),
        z,
      );
      final ok = _map.move(center, z);
      if (!ok) {
        _map.move(ll, z, offset: Offset(0, offsetY));
      }
    } catch (_) {
      try {
        _map.move(ll, z, offset: Offset(0, offsetY));
      } catch (_) {
        _map.move(ll, z);
      }
    }
    _clearProg();
  }

  void _clearProg() {
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      _programmaticMove = false;
    });
  }

  /// Locate button — [bandTop]/[bandBottom] = live measure from parent.
  void centerOnMe({
    bool animated = true,
    double? bandTop,
    double? bandBottom,
  }) {
    final me = _me;
    if (me == null) {
      locate(
        forceCamera: true,
        bandTop: bandTop,
        bandBottom: bandBottom,
      );
      return;
    }
    _centerOn(
      me,
      zoom: 15.5,
      bandTop: bandTop,
      bandBottom: bandBottom,
    );
  }

  Future<void> locate({
    bool forceCamera = false,
    double? bandTop,
    double? bandBottom,
  }) async {
    if (_locating) return;
    _pendingBandTop = bandTop;
    _pendingBandBottom = bandBottom;
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

      _applyPosition(pos, moveCamera: forceCamera || !_didInitialRecenter);
      widget.onLocateState?.call(false, null);

      await _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen(
        (p) => _applyPosition(p, moveCamera: false),
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
      final t = _pendingBandTop;
      final b = _pendingBandBottom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _centerOn(ll, zoom: 15.5, bandTop: t, bandBottom: b);
        }
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
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.recordo',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        MarkerLayer(markers: markers),
        const SimpleAttributionWidget(
          source: Text('© OSM · CARTO'),
          backgroundColor: Color(0x66000000),
        ),
      ],
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
