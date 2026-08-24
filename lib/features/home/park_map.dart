import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park.dart';

/// Real map tiles (OSM) + parking pins. No Google key needed for dogfood.
/// Later: swap TileLayer URL / add Google if CEO provides key.
class ParkMap extends StatelessWidget {
  const ParkMap({
    super.key,
    required this.parks,
    this.selectedId,
    this.onSelect,
  });

  final List<Park> parks;
  final String? selectedId;
  final ValueChanged<String>? onSelect;

  static const _hk = LatLng(22.3193, 114.1694);

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      for (final p in parks)
        Marker(
          point: LatLng(p.lat, p.lng),
          width: p.id == selectedId ? 48 : 40,
          height: p.id == selectedId ? 48 : 40,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => onSelect?.call(p.id),
            child: _ParkPin(selected: p.id == selectedId),
          ),
        ),
    ];

    LatLng center = _hk;
    if (selectedId != null) {
      final s = parks.where((e) => e.id == selectedId).firstOrNull;
      if (s != null) center = LatLng(s.lat, s.lng);
    } else if (parks.isNotEmpty) {
      center = LatLng(parks.first.lat, parks.first.lng);
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12.2,
        minZoom: 10,
        maxZoom: 18,
        backgroundColor: UberColors.mapBlock,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          // Carto dark matter — Uber-ish dark streets
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.recordo',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        MarkerLayer(markers: markers),
        // light attribution (OSM/Carto require credit)
        const SimpleAttributionWidget(
          source: Text('© OSM · CARTO'),
          backgroundColor: Color(0x66000000),
        ),
      ],
    );
  }
}

class _ParkPin extends StatelessWidget {
  const _ParkPin({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = selected ? 44.0 : 36.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: selected ? UberColors.accent : UberColors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: UberColors.black.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      child: Icon(
        Icons.local_parking_rounded,
        size: selected ? 22 : 18,
        color: UberColors.black,
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
