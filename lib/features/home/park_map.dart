import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park.dart';

/// Dark map + pins + GPS. Center “big pin” like Google/Uber destination sample.
class ParkMap extends StatefulWidget {
  const ParkMap({
    super.key,
    required this.parks,
    this.selectedId,
    this.onSelect,
    this.onUserLocation,
    this.onPinMoved,
  });

  final List<Park> parks;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final ValueChanged<LatLng>? onUserLocation;
  final ValueChanged<LatLng>? onPinMoved;

  @override
  State<ParkMap> createState() => ParkMapState();
}

class ParkMapState extends State<ParkMap> {
  static const hkCenter = LatLng(22.3193, 114.1694);

  final _map = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  bool _locating = false;
  String? _locError;
  bool _didInitialRecenter = false;
  bool _mapMoving = false;

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
    if (widget.selectedId != null &&
        widget.selectedId != oldWidget.selectedId) {
      final p =
          widget.parks.where((e) => e.id == widget.selectedId).firstOrNull;
      if (p != null) {
        _map.move(LatLng(p.lat, p.lng), _map.camera.zoom.clamp(14.0, 16.5));
        widget.onPinMoved?.call(LatLng(p.lat, p.lng));
      }
    }
  }

  Future<void> locate({bool forceCamera = false}) async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locError = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => _locError = '請開定位服務');
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        setState(() => _locError = '未有定位權限');
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _locError = '請去設定開定位');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      _applyPosition(pos, moveCamera: forceCamera || !_didInitialRecenter);

      await _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 12,
        ),
      ).listen(
        (p) => _applyPosition(p, moveCamera: false),
        onError: (_) {},
      );
    } catch (_) {
      if (mounted) setState(() => _locError = '定位失敗');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _applyPosition(Position pos, {required bool moveCamera}) {
    final ll = LatLng(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _me = ll;
      _locError = null;
    });
    widget.onUserLocation?.call(ll);
    if (moveCamera) {
      _didInitialRecenter = true;
      _map.move(ll, 15);
      widget.onPinMoved?.call(ll);
    }
  }

  void _onMapEvent(MapEvent e) {
    if (e is MapEventMoveStart) {
      setState(() => _mapMoving = true);
    } else if (e is MapEventMoveEnd) {
      setState(() => _mapMoving = false);
      final c = _map.camera.center;
      widget.onPinMoved?.call(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      for (final p in widget.parks)
        Marker(
          point: LatLng(p.lat, p.lng),
          width: p.id == widget.selectedId ? 44 : 36,
          height: p.id == widget.selectedId ? 44 : 36,
          alignment: Alignment.topCenter,
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

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _me ?? hkCenter,
            initialZoom: 14.5,
            minZoom: 10,
            maxZoom: 18,
            backgroundColor: UberColors.mapBlock,
            onMapEvent: _onMapEvent,
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
        ),

        // Fixed center pin (sample: drag map to move pin)
        IgnorePointer(
          child: Center(
            child: Padding(
              // lift so tip sits on true center
              padding: EdgeInsets.only(bottom: _mapMoving ? 12 : 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: UberColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: UberColors.black.withValues(alpha: 0.2),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_parking_rounded,
                        color: UberColors.black,
                        size: 24,
                      ),
                    ),
                    Container(
                      width: 3,
                      height: 14,
                      color: UberColors.white,
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          right: 16,
          bottom: MediaQuery.sizeOf(context).height * 0.48 + 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_locError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: UberColors.sheet.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _locError!,
                    style: const TextStyle(
                      color: UberColors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Material(
                color: UberColors.sheet.withValues(alpha: 0.95),
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _locating ? null : () => locate(forceCamera: true),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: _locating
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: UberColors.white,
                            ),
                          )
                        : const Icon(
                            Icons.my_location_rounded,
                            color: UberColors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
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
    final s = selected ? 40.0 : 32.0;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: selected ? UberColors.accent : UberColors.elevated2,
        shape: BoxShape.circle,
        border: Border.all(color: UberColors.white.withValues(alpha: 0.35)),
      ),
      child: Icon(
        Icons.local_parking_rounded,
        size: selected ? 20 : 16,
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
