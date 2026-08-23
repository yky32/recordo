import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park.dart';

/// Dark “city map” canvas — Uber density without Maps SDK key.
class UberMapCanvas extends StatelessWidget {
  const UberMapCanvas({
    super.key,
    required this.parks,
    this.selectedId,
    this.onSelect,
  });

  final List<Park> parks;
  final String? selectedId;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          onTapUp: (d) {
            // tap empty → deselect handled by parent via null if needed
          },
          child: CustomPaint(
            painter: _MapPainter(parks: parks, selectedId: selectedId),
            child: Stack(
              children: [
                for (final p in parks)
                  _Pin(
                    park: p,
                    selected: p.id == selectedId,
                    size: Size(c.maxWidth, c.maxHeight),
                    onTap: () => onSelect?.call(p.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({
    required this.park,
    required this.selected,
    required this.size,
    required this.onTap,
  });

  final Park park;
  final bool selected;
  final Size size;
  final VoidCallback onTap;

  Offset _xy() {
    // Rough HK bounding box → screen
    const minLat = 22.20, maxLat = 22.52;
    const minLng = 113.85, maxLng = 114.35;
    final nx = ((park.lng - minLng) / (maxLng - minLng)).clamp(0.05, 0.95);
    final ny = (1 - (park.lat - minLat) / (maxLat - minLat)).clamp(0.08, 0.75);
    return Offset(nx * size.width, ny * size.height);
  }

  @override
  Widget build(BuildContext context) {
    final o = _xy();
    final s = selected ? 44.0 : 34.0;
    return Positioned(
      left: o.dx - s / 2,
      top: o.dy - s,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
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
            color: selected ? UberColors.black : UberColors.black,
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.parks, this.selectedId});

  final List<Park> parks;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = UberColors.mapBlock;
    canvas.drawRect(Offset.zero & size, bg);

    final road = Paint()
      ..color = UberColors.mapRoad
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final roadThin = Paint()
      ..color = UberColors.mapGrid
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Pseudo street grid
    for (var i = 0; i < 8; i++) {
      final y = size.height * (0.12 + i * 0.1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + (i.isEven ? 12 : -8)), road);
    }
    for (var i = 0; i < 6; i++) {
      final x = size.width * (0.1 + i * 0.15);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + math.sin(i.toDouble()) * 30, size.height),
        roadThin,
      );
    }

    // Soft vignette
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.55),
        ],
        radius: 0.95,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.selectedId != selectedId ||
      oldDelegate.parks.length != parks.length;
}
