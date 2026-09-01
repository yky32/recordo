import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/location/user_location.dart';
import 'package:recordo/core/navigation/park_navigation.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/features/home/map_pins.dart';
import 'package:recordo/features/home/park_clusters.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/meter_space.dart';

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
    this.meterSpaces = const [],
    this.meterOccupancy = const {},
    this.selectedMeterId,
    this.onSelectMeter,
    this.onMeterViewport,
    this.destLat,
    this.destLng,
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
  final List<MeterSpace> meterSpaces;
  final Map<String, MeterOccupancy> meterOccupancy;
  final String? selectedMeterId;
  final ValueChanged<String>? onSelectMeter;
  final void Function({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    required double zoom,
  })? onMeterViewport;
  final double? destLat;
  final double? destLng;

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
  final _meterShownAt = <String, LatLng>{};

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
    if (widget.destLat != null &&
        widget.destLng != null &&
        (widget.destLat != oldWidget.destLat ||
            widget.destLng != oldWidget.destLng)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          centerOn(LatLng(widget.destLat!, widget.destLng!), zoom: 16.2);
        }
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

  void centerOn(LatLng ll, {double zoom = 16.2}) {
    _animateTo(ll, zoom: zoom);
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
      final result = await UserLocationResolver.resolve();
      if (result.error != null) {
        widget.onLocateState?.call(false, result.error);
        return;
      }
      if (!result.ok) {
        widget.onLocateState?.call(false, '定位失敗 · 再試');
        return;
      }
      if (result.demo) {
        widget.onLocateState?.call(false, null);
        return;
      }

      final pos = Position(
        latitude: result.lat!,
        longitude: result.lng!,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

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
      _emitMeterViewport();
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
        _emitMeterViewport();
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
      final pick = c.parks.firstWhere(
        (p) => p.isVerifiedPrice,
        orElse: () => c.parks.firstWhere(
          (p) => p.hasUgcReports,
          orElse: () => c.primary,
        ),
      );
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

  void _emitMeterViewport() {
    try {
      final cam = _map.camera;
      final b = cam.visibleBounds;
      widget.onMeterViewport?.call(
        minLat: b.south,
        minLng: b.west,
        maxLat: b.north,
        maxLng: b.east,
        zoom: cam.zoom,
      );
    } catch (_) {}
  }

  List<Marker> _meterMarkers() {
    _meterShownAt.clear();
    var z = 16.0;
    try {
      z = _map.camera.zoom;
    } catch (_) {}
    if (z < 16) return const [];
    if (widget.meterSpaces.isEmpty) return const [];

    // Occupied is 90% of the candy (CEO 軒尼詩). Map = vacant only, like HKeMeter far zoom.
    final poles = <String, List<MeterSpace>>{};
    for (final m in widget.meterSpaces) {
      final pole = (m.poleId ?? '').trim();
      final k = pole.isEmpty ? m.id : pole;
      (poles[k] ??= []).add(m);
    }

    MeterBayStatus statusOf(List<MeterSpace> bays) {
      var vacant = false;
      var occupied = false;
      for (final m in bays) {
        final s = widget.meterOccupancy[m.id]?.status ??
            MeterBayStatus.suspended;
        if (s == MeterBayStatus.vacant) vacant = true;
        if (s == MeterBayStatus.occupied) occupied = true;
      }
      if (vacant) return MeterBayStatus.vacant;
      if (occupied) return MeterBayStatus.occupied;
      return MeterBayStatus.suspended;
    }

    MeterSpace tapBay(List<MeterSpace> bays) {
      for (final m in bays) {
        if (widget.meterOccupancy[m.id]?.status == MeterBayStatus.vacant) {
          return m;
        }
      }
      return bays.first;
    }

    final lat0 = widget.meterSpaces.first.lat;
    final cosLat = math.cos(lat0 * math.pi / 180).clamp(0.25, 1.0);
    final mPerPx = 156543.03392 * cosLat / math.pow(2, z);
    final cellLat = (mPerPx * 18) / 111320.0;
    final cellLng = cellLat / cosLat;
    final groups = <String, List<List<MeterSpace>>>{};
    for (final bays in poles.values) {
      final st = statusOf(bays);
      if (st != MeterBayStatus.vacant) continue;
      var lat = 0.0, lng = 0.0;
      for (final m in bays) {
        lat += m.lat;
        lng += m.lng;
      }
      lat /= bays.length;
      lng /= bays.length;
      final k = '${(lat / cellLat).round()},${(lng / cellLng).round()}';
      (groups[k] ??= []).add(bays);
    }

    final vacant = <Marker>[];
    final rest = <Marker>[];
    for (final g in groups.values) {
      final n = g.length;
      final origin = g.first;
      var oLat = 0.0, oLng = 0.0;
      for (final b in origin) {
        oLat += b.lat;
        oLng += b.lng;
      }
      oLat /= origin.length;
      oLng /= origin.length;
      final radiusPx = n <= 1
          ? 0.0
          : math.min(64.0, math.max(28.0, (n * 20) / (2 * math.pi)));
      final rLat = (mPerPx * radiusPx) / 111320.0;
      final rLng = rLat / cosLat;
      for (var i = 0; i < n; i++) {
        final bays = g[i];
        var lat = oLat;
        var lng = oLng;
        if (n > 1) {
          final ring = i ~/ 12;
          final idx = i % 12;
          final onRing = math.min(12, n - ring * 12);
          final a = (2 * math.pi * idx) / onRing;
          final scale = 1.0 + ring * 0.75;
          lat += rLat * scale * math.sin(a);
          lng += rLng * scale * math.cos(a);
        }
        final m = tapBay(bays);
        final st = statusOf(bays);
        final pt = LatLng(lat, lng);
        for (final b in bays) {
          _meterShownAt[b.id] = pt;
        }
        final marker = Marker(
          point: pt,
          width: 18,
          height: 18,
          alignment: Alignment.center,
          child: MeterBayDot(
            status: st,
            selected: bays.any((b) => b.id == widget.selectedMeterId),
            onTap: () => widget.onSelectMeter?.call(
              m.id == widget.selectedMeterId ? '' : m.id,
            ),
          ),
        );
        if (st == MeterBayStatus.vacant) {
          vacant.add(marker);
        } else {
          rest.add(marker);
        }
      }
    }
    return [...rest, ...vacant];
  }

  Widget _meterCalloutOverlay() {
    final id = widget.selectedMeterId;
    if (id == null || id.isEmpty) return const SizedBox.shrink();
    MeterSpace? m;
    for (final e in widget.meterSpaces) {
      if (e.id == id) {
        m = e;
        break;
      }
    }
    if (m == null) return const SizedBox.shrink();
    final pt = _meterShownAt[m.id] ?? LatLng(m.lat, m.lng);
    Offset screen;
    try {
      screen = _map.camera.latLngToScreenOffset(pt);
    } catch (_) {
      return const SizedBox.shrink();
    }

    const cardW = 228.0;
    const cardH = 176.0;
    final size = MediaQuery.sizeOf(context);
    final topMin = math.max(8.0, widget.bandTopY.value + 8);
    var botMax = widget.bandBottomY.value;
    if (botMax <= topMin + 40) botMax = size.height - 24;
    botMax -= 8;
    const leftMin = 8.0;
    final rightMax = size.width - 8;

    var left = screen.dx + 16;
    if (left + cardW > rightMax) {
      left = screen.dx - 16 - cardW;
    }
    if (left < leftMin) left = leftMin;
    if (left + cardW > rightMax) left = rightMax - cardW;

    var top = screen.dy - cardH / 2;
    final maxTop = math.max(topMin, botMax - cardH);
    if (top < topMin) top = topMin;
    if (top > maxTop) top = maxTop;

    return Positioned(
      left: left,
      top: top,
      width: cardW,
      child: MeterCallout(
        space: m,
        status: widget.meterOccupancy[m.id]?.status,
        onClose: () => widget.onSelectMeter?.call(''),
        onPay: ParkNavigation.openHkeMeter,
        onRoute: () => ParkNavigation.showChooserAt(
          context,
          lat: m!.lat,
          lng: m.lng,
          name: '咪錶 ${m.id}',
        ),
      ),
    );
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
      final showChip = selected || p.showAsMapPriceChip;
      final marker = Marker(
        point: LatLng(p.lat, p.lng),
        width: selected ? 160 : (showChip ? (p.hasEvCharging ? 86 : 72) : 32),
        height: selected ? 78 : (showChip ? 36 : 32),
        alignment:
            showChip || selected ? Alignment.bottomCenter : Alignment.center,
        child: showChip
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
      listenable: Listenable.merge([
        ThemeController.instance,
        widget.bandTopY,
        widget.bandBottomY,
      ]),
      builder: (context, _) {
        final tileUrl = UberColors.mapTileUrl;
        return Stack(
          children: [
            FlutterMap(
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
                  maxNativeZoom: UberColors.mapMaxNativeZoom,
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
                if (selectedMarker != null)
                  MarkerLayer(markers: [selectedMarker]),
                MarkerLayer(markers: _meterMarkers()),
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
            ),
            _meterCalloutOverlay(),
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
