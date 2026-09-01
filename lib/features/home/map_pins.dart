import 'package:flutter/material.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/features/home/park_clusters.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/meter_space.dart';

const googleBlue = Color(0xFF4285F4);

class MeLocationDot extends StatefulWidget {
  const MeLocationDot({super.key});

  @override
  State<MeLocationDot> createState() => _MeLocationDotState();
}

class _MeLocationDotState extends State<MeLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_pulse.value);
        return SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 18 + 22 * t,
                height: 18 + 22 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: googleBlue.withValues(alpha: (1 - t) * 0.28),
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: googleBlue,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 8,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ParkDot extends StatelessWidget {
  const ParkDot({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark;
    final fill = dark ? const Color(0xF21C1C1E) : Colors.white;
    final fg = dark ? Colors.white : const Color(0xFF111111);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.82)
                    : const Color(0xFF111111),
                width: 1.25,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.local_parking_rounded,
              size: 15,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class ParkPriceChip extends StatelessWidget {
  const ParkPriceChip({
    super.key,
    required this.park,
    required this.selected,
    required this.onTap,
  });

  final Park park;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = pinPriceLabel(park);
    final fill = selected ? UberColors.accent : Colors.white;
    final fg = selected ? Colors.white : const Color(0xFF111111);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: UberColors.sheet,
                elevation: 6,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      park.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: UberColors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 9 : 7,
              vertical: selected ? 5 : 3.5,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? null
                  : Border.all(color: const Color(0x14000000)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: selected ? 0.35 : 0.22),
                  blurRadius: selected ? 10 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (park.hasEvCharging) ...[
                  Icon(Icons.bolt_rounded, size: selected ? 14 : 12, color: fg),
                  SizedBox(width: selected ? 3 : 2),
                ],
                Text(
                  label.isEmpty ? 'P' : label,
                  style: TextStyle(
                    color: fg,
                    fontSize: selected ? 13 : 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(10, 6),
            painter: _ChipPointerPainter(fill),
          ),
        ],
      ),
    );
  }
}

class ParkClusterChip extends StatelessWidget {
  const ParkClusterChip({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark;
    final s = count >= 20 ? 40.0 : (count >= 8 ? 36.0 : 32.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? const Color(0xF21C1C1E) : Colors.white,
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.18)
                : const Color(0x22000000),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            color: dark ? Colors.white : const Color(0xFF111111),
            fontSize: count >= 20 ? 12 : 13,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class MeterChip extends StatelessWidget {
  const MeterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = selected ? const Color(0xFF3D7A5A) : Colors.white;
    final fg = selected ? Colors.white : const Color(0xFF111111);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Text(
              '咪 $label',
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(10, 6),
            painter: _ChipPointerPainter(fill),
          ),
        ],
      ),
    );
  }
}

class MeterBayDot extends StatelessWidget {
  const MeterBayDot({
    super.key,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final MeterBayStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MeterBayStatus.vacant => const Color(0xFF2FA86B),
      MeterBayStatus.occupied => const Color(0xFFE24B4A),
      MeterBayStatus.suspended => const Color(0xFF8A8A8A),
    };
    final occupied = status == MeterBayStatus.occupied && !selected;
    final size = selected
        ? 16.0
        : occupied
            ? 7.0
            : 12.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Opacity(
            opacity: occupied ? 0.4 : 1,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: occupied
                    ? null
                    : Border.all(
                        color: Colors.white,
                        width: selected ? 2 : 1.2,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MeterCallout extends StatelessWidget {
  const MeterCallout({
    super.key,
    required this.space,
    required this.status,
    required this.onClose,
    required this.onPay,
    required this.onRoute,
  });

  final MeterSpace space;
  final MeterBayStatus? status;
  final VoidCallback onClose;
  final VoidCallback onPay;
  final VoidCallback onRoute;

  @override
  Widget build(BuildContext context) {
    final occ = switch (status) {
      MeterBayStatus.vacant => '空置',
      MeterBayStatus.occupied => '已使用',
      MeterBayStatus.suspended => '暫停',
      null => '無數據',
    };
    final occColor = switch (status) {
      MeterBayStatus.vacant => const Color(0xFF2FA86B),
      MeterBayStatus.occupied => const Color(0xFFE24B4A),
      MeterBayStatus.suspended => const Color(0xFF8A8A8A),
      null => UberColors.muted,
    };
    final stay = space.lppLabel.replaceFirst('最長停泊時間 ', '');
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 228,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        decoration: BoxDecoration(
          color: UberColors.sheet,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: UberColors.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(space.id, style: RType.titleSm()),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: Icon(Icons.close, size: 16, color: UberColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(space.placeLine, style: RType.muted(), maxLines: 2),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: occColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    occ,
                    style: RType.label().copyWith(color: occColor, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Text(stay, style: RType.label()),
              ],
            ),
            const SizedBox(height: 4),
            Text(space.feeLabel.replaceFirst(' - ', ' / '), style: RType.body()),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: UberColors.ctaFill,
                      foregroundColor: UberColors.ctaOnFill,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: onPay,
                    child: const Text('入錶易', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: UberColors.white,
                      side: BorderSide(color: UberColors.hairline),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: onRoute,
                    child: const Text('路線', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipPointerPainter extends CustomPainter {
  _ChipPointerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ChipPointerPainter old) => old.color != color;
}
