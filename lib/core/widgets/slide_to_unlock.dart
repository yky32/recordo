import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';

/// Uber-style horizontal slide-to-confirm (full travel required).
class SlideToUnlock extends StatefulWidget {
  const SlideToUnlock({
    super.key,
    required this.label,
    required this.onCompleted,
    this.enabled = true,
    this.accent,
    this.trackColor,
    this.thumbColor,
    this.height = 64,
  });

  final String label;
  final VoidCallback onCompleted;
  final bool enabled;
  final Color? accent;
  final Color? trackColor;
  final Color? thumbColor;
  final double height;

  @override
  State<SlideToUnlock> createState() => _SlideToUnlockState();
}

class _SlideToUnlockState extends State<SlideToUnlock>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  late final AnimationController _snap;
  void Function()? _tick;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    if (_tick != null) {
      _snap.removeListener(_tick!);
      _tick = null;
    }
    _snap.dispose();
    super.dispose();
  }

  void _reset() {
    if (!mounted) return;
    final start = _dx;
    if (_tick != null) {
      _snap.removeListener(_tick!);
    }
    _tick = () {
      if (!mounted) return;
      setState(() => _dx = start * (1 - _snap.value));
    };
    _snap
      ..reset()
      ..addListener(_tick!);
    _snap.forward().whenComplete(() {
      if (!mounted) return;
      if (_tick != null) {
        _snap.removeListener(_tick!);
        _tick = null;
      }
      setState(() => _dx = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? UberColors.ctaFill;
    final track = widget.trackColor ?? UberColors.elevated2;
    final thumbIcon = widget.thumbColor ?? UberColors.ctaOnFill;

    return LayoutBuilder(
      builder: (context, c) {
        final h = widget.height;
        final thumb = h - 8;
        final maxDx = (c.maxWidth - thumb - 8).clamp(0.0, 1000.0);
        final progress = maxDx <= 0 ? 0.0 : (_dx / maxDx).clamp(0.0, 1.0);

        return Opacity(
          opacity: widget.enabled ? 1 : 0.45,
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(h / 2),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(h / 2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        heightFactor: 1,
                        child: ColoredBox(
                          color: accent.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    widget.label,
                    style: RType.titleSm().copyWith(
                      color: UberColors.white.withValues(
                        alpha: 0.35 + 0.45 * (1 - progress),
                      ),
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Positioned(
                  right: 22,
                  child: Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    color: UberColors.muted.withValues(alpha: 0.5),
                  ),
                ),
                Positioned(
                  left: 4 + _dx,
                  child: GestureDetector(
                    onHorizontalDragUpdate: widget.enabled
                        ? (d) {
                            setState(() {
                              _dx = (_dx + d.delta.dx).clamp(0.0, maxDx);
                            });
                          }
                        : null,
                    onHorizontalDragEnd: widget.enabled
                        ? (_) {
                            if (_dx >= maxDx * 0.92) {
                              HapticFeedback.mediumImpact();
                              setState(() => _dx = maxDx);
                              widget.onCompleted();
                              Future<void>.delayed(
                                const Duration(milliseconds: 120),
                                () {
                                  if (mounted) _reset();
                                },
                              );
                            } else {
                              HapticFeedback.selectionClick();
                              _reset();
                            }
                          }
                        : null,
                    child: Container(
                      width: thumb,
                      height: thumb,
                      decoration: BoxDecoration(
                        color: widget.enabled ? accent : UberColors.muted,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: thumbIcon,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
