import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/features/home/map_pins.dart';
import 'package:recordo/features/home/park_clusters.dart';
import 'package:recordo/features/parks/park.dart';

/// Full-screen map. Parent overlays search/sheet.
/// Band notifiers are read only when centering — sheet drag must not rebuild tiles.
class ParkMap extends StatefulWidget {
  const ParkMap({
    super.key,
    required this.parks,
    required this.bandTopY,
    required this.bandBottomY,
    this.selectedId,
    this.onSelect,
    this.onUserLocation,
    this.onPinMoved,
    this.onLocateState,
    this.onMapInteraction,
  });

  final List<Park> parks;
  final String? selectedId;
  final ValueNotifier<double> bandTopY;
  final ValueNotifier<double> bandBottomY;
  final ValueChanged<String>? onSelect;
  final ValueChanged<LatLng>? onUserLocation;
  final ValueChanged<LatLng>? onPinMoved;
  final void Function(bool locating, String? error)? onLocateState;
  final VoidCallback? onMapInteraction;

  @override
  State<ParkMap> createState() => ParkMapState();
}

class ParkMapState extends State<ParkMap> with TickerProviderStateMixin {
  static const hkCenter = LatLng(22.3193, 114.1694);

  final _map = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  double _accuracyM = 40;
  bool _locating = false;
  bool _didInitialRecenter = false;
  bool _programmaticMove = false;
  AnimationController? _camAnim;
  Timer? _pinDebounce;

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
    _pinDebounce?.cancel();
    _camAnim?.dispose();
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
    _animateTo(LatLng(p.lat, p.lng), zoom: 17.4);
  }

  void centerOnMe({bool animated = true}) {
    final me = _me;
    if (me == null) {
      locate(forceCamera: true);
      return;
    }
    _animateTo(me, zoom: 16.2);
  }

  Offset _bandOffset(double mapH) {
    var top = widget.bandTopY.value;
    var bottom = widget.bandBottomY.value;
    if (!top.isFinite || !bottom.isFinite || bottom <= top + 60) {
      top = mapH * 0.14;
      bottom = mapH * 0.55;
    }
    final targetY = top + (bottom - top) * 0.42;
    return Offset(0, targetY - mapH / 2);
  }

  LatLng _cameraCenterFor(LatLng ll, double z, Size mapSize) {
    try {
      final cam = _map.camera;
      final offsetY = _bandOffset(mapSize.height).dy;
      final newPoint = cam.projectAtZoom(ll, z);
      return cam.unprojectAtZoom(newPoint - Offset(0, offsetY), z);
    } catch (_) {
      return ll;
    }
  }

  void _animateTo(LatLng ll, {double? zoom}) {
    if (!mounted) return;
    final z = (zoom ?? 16.0).clamp(13.5, 18.0);
    final h = MediaQuery.sizeOf(context).height;
    final w = MediaQuery.sizeOf(context).width;
    LatLng dest;
    double fromZ;
    LatLng from;
    try {
      from = _map.camera.center;
      fromZ = _map.camera.zoom;
      dest = _cameraCenterFor(ll, z, Size(w, h));
    } catch (_) {
      _moveNow(ll, z);
      return;
    }

    _camAnim?.stop();
    _camAnim?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _camAnim = ctrl;
    final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);
    _programmaticMove = true;
    ctrl.addListener(() {
      if (!mounted) return;
      final t = curve.value;
      final lat = from.latitude + (dest.latitude - from.latitude) * t;
      final lng = from.longitude + (dest.longitude - from.longitude) * t;
      final zz = fromZ + (z - fromZ) * t;
      try {
        _map.move(LatLng(lat, lng), zz);
      } catch (_) {}
    });
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        _programmaticMove = false;
      }
    });
    ctrl.forward();
  }

  void _moveNow(LatLng ll, double z) {
    _programmaticMove = true;
    try {
      final h = MediaQuery.sizeOf(context).height;
      _map.move(ll, z, offset: _bandOffset(h));
    } catch (_) {
      try {
        _map.move(ll, z);
      } catch (_) {}
    }
    Future<void>.delayed(const Duration(milliseconds: 160), () {
      _programmaticMove = false;
    });
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
    setState(() {
      _me = ll;
      _accuracyM = pos.accuracy.clamp(18, 80);
    });
    widget.onUserLocation?.call(ll);
    if (moveCamera) {
      _didInitialRecenter = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(ll, zoom: 16.2);
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
    if (e is MapEventMoveEnd || e is MapEventFlingAnimationEnd) {
      if (mounted) setState(() {});
      final center = _map.camera.center;
      _pinDebounce?.cancel();
      _pinDebounce = Timer(const Duration(milliseconds: 380), () {
        if (!mounted) return;
        widget.onPinMoved?.call(center);
      });
    }
  }

  List<ParkCluster> _clusters() {
    try {
      final cam = _map.camera;
      if (cam.nonRotatedSize.width <= 0) {
        return [
          for (final p in widget.parks)
            ParkCluster(parks: [p], center: LatLng(p.lat, p.lng)),
        ];
      }
      final bounds = cam.visibleBounds;
      final visible = <Park>[];
      for (final p in widget.parks) {
        if (p.id == widget.selectedId ||
            bounds.contains(LatLng(p.lat, p.lng))) {
          visible.add(p);
        }
      }
      return clusterParks(
        parks: visible,
        toScreen: cam.latLngToScreenOffset,
        radiusPx: clusterRadiusPx(cam.zoom),
        keepSeparateId: widget.selectedId,
      );
    } catch (_) {
      return [
        for (final p in widget.parks.take(40))
          ParkCluster(parks: [p], center: LatLng(p.lat, p.lng)),
      ];
    }
  }

  void _onClusterTap(ParkCluster c) {
    if (c.isSingle) {
      widget.onSelect?.call(c.primary.id);
      return;
    }
    // OSM duplicates stacked on one lot — pick a park instead of fighting zoom.
    if (clusterSpanM(c) < 28) {
      final pick = c.parks.firstWhere((p) => p.hasPrice, orElse: () => c.primary);
      widget.onSelect?.call(pick.id);
      return;
    }
    try {
      final pts = c.parks.map((p) => LatLng(p.lat, p.lng)).toList();
      _programmaticMove = true;
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: pts,
          padding: const EdgeInsets.fromLTRB(48, 120, 48, 220),
          maxZoom: 17.8,
        ),
      );
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        _programmaticMove = false;
        if (mounted) setState(() {});
      });
    } catch (_) {
      widget.onSelect?.call(c.primary.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clusters = _clusters();
    final clusterMarkers = <Marker>[];
    final pinMarkers = <Marker>[];
    Marker? selectedMarker;

    for (final c in clusters) {
      if (!c.isSingle) {
        clusterMarkers.add(
          Marker(
            point: c.center,
            width: 42,
            height: 42,
            alignment: Alignment.center,
            child: ParkClusterChip(
              count: c.parks.length,
              onTap: () => _onClusterTap(c),
            ),
          ),
        );
        continue;
      }
      final p = c.primary;
      final selected = p.id == widget.selectedId;
      final marker = Marker(
        point: LatLng(p.lat, p.lng),
        width: selected ? 160 : (p.hasPrice ? 72 : 28),
        height: selected ? 78 : (p.hasPrice ? 36 : 28),
        alignment: p.hasPrice || selected ? Alignment.bottomCenter : Alignment.center,
        child: selected || p.hasPrice
            ? ParkPriceChip(
                park: p,
                selected: selected,
                onTap: () => widget.onSelect?.call(p.id),
              )
            : ParkDot(onTap: () => widget.onSelect?.call(p.id)),
      );
      if (selected) {
        selectedMarker = marker;
      } else {
        pinMarkers.add(marker);
      }
    }

    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final tileUrl = UberColors.mapTileUrl;
        return FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _me ?? hkCenter,
            initialZoom: 15.8,
            minZoom: 11,
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
              urlTemplate: tileUrl,
              fallbackUrl: UberColors.mapTileFallback,
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
            if (_me != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _me!,
                    radius: _accuracyM,
                    useRadiusInMeter: true,
                    color: googleBlue.withValues(alpha: 0.12),
                    borderStrokeWidth: 1,
                    borderColor: googleBlue.withValues(alpha: 0.22),
                  ),
                ],
              ),
            MarkerLayer(markers: pinMarkers),
            MarkerLayer(markers: clusterMarkers),
            if (selectedMarker != null) MarkerLayer(markers: [selectedMarker]),
            if (_me != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _me!,
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    child: const MeLocationDot(),
                  ),
                ],
              ),
          ],
        );
      },
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
