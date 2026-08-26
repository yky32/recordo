import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:recordo/app/routes.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/core/widgets/slide_to_unlock.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/end_session_sheet.dart';
import 'package:recordo/features/session/session_cubit.dart';

/// Full-screen live parking timer — duration + estimated fee.
class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _end() async {
    final ok = await showEndSessionSheet(context);
    if (ok && mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final top = MediaQuery.paddingOf(context).top;

    return BlocBuilder<SessionCubit, SessionState>(
      builder: (context, session) {
        final active = session.active;
        if (active == null) {
          // Ended elsewhere
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && context.canPop()) context.pop();
          });
          return Scaffold(
            backgroundColor: UberColors.black,
            body: Center(child: Text('未有進行中', style: RType.muted())),
          );
        }

        final park = active.parkId != null
            ? context.read<ParkCatalogCubit>().parkById(active.parkId!)
            : null;
        final name = active.parkName ?? park?.name ?? '停車場';
        final elapsed = active.elapsed;
        final timeLabel = formatSessionDuration(elapsed);
        final hourly = park?.hourlyHkd;
        final est = estimateParkingFee(elapsed, hourly);
        final started = active.startedAt;
        final startLabel =
            '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')} 開始';

        return Scaffold(
          backgroundColor: UberColors.black,
          // Sheet owns the keyboard — don't crush the timer behind it.
          resizeToAvoidBottomInset: false,
          body: Column(
            children: [
              SizedBox(height: top + 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: Icon(Icons.close_rounded, color: UberColors.white),
                    ),
                    Expanded(
                      child: Text(
                        '計時中',
                        textAlign: TextAlign.center,
                        style: RType.titleSm(),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: CustomScrollView(
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Column(
                          children: [
                            const Spacer(flex: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: UberColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: UberColors.accent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: UberColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'LIVE',
                              style: RType.label().copyWith(
                                color: UberColors.accent,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: RType.title(),
                      ),
                      const SizedBox(height: 8),
                      Text(startLabel, style: RType.muted()),
                      const SizedBox(height: 36),
                      Text(
                        '泊咗',
                        style: RType.label(),
                      ),
                      const SizedBox(height: 8),
                      // Giant timer
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          timeLabel,
                          style: GoogleFonts.syne(
                            fontSize: 72,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -2,
                            height: 1.0,
                            color: UberColors.white,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      // Fee card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        decoration: BoxDecoration(
                          color: UberColors.elevated,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: UberColors.hairline),
                        ),
                        child: Column(
                          children: [
                            Text('預估總費', style: RType.muted()),
                            const SizedBox(height: 10),
                            if (est != null) ...[
                              Text(
                                'HK\$${est.toStringAsFixed(0)}',
                                style: GoogleFonts.syne(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1,
                                  color: UberColors.accent,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '按 HK\$${hourly!.toStringAsFixed(0)}/時 · 約數，以閘口為準',
                                textAlign: TextAlign.center,
                                style: RType.muted(),
                              ),
                            ] else ...[
                              Text(
                                '—',
                                style: GoogleFonts.syne(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w700,
                                  color: UberColors.muted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '未有時租 · 完結時自己填實際收費',
                                textAlign: TextAlign.center,
                                style: RType.muted(),
                              ),
                            ],
                          ],
                        ),
                      ),
                            const Spacer(flex: 3),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (park != null)
                      TextButton(
                        onPressed: () => context.push(parkDetailLocation(park.id)),
                        child: Text('睇場詳情', style: RType.body()),
                      ),
                    const SizedBox(height: 4),
                    SlideToUnlock(
                      label: '右滑結束 · 填收費',
                      height: 58,
                      accent: UberColors.accent,
                      thumbColor: UberColors.ctaOnFill,
                      trackColor: ThemeController.instance.isDark
                          ? const Color(0xFF0A2A1A)
                          : const Color(0xFFD4F5E4),
                      onCompleted: () {
                        HapticFeedback.mediumImpact();
                        _end();
                      },
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
