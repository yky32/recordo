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
import 'package:recordo/features/session/parking_session.dart';
import 'package:recordo/features/session/session_alarm_service.dart';
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

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: UberColors.sheet,
        title: Text('取消今次計時？', style: RType.titleSm()),
        content: Text(
          '當誤撳開始。唔會記入過往記錄。',
          style: RType.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('繼續計時', style: RType.body()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '取消計時',
              style: RType.body().copyWith(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<SessionCubit>().discardActive();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _editStart(DateTime current) async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: UberColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        Widget chip(String label, Duration back) {
          return ActionChip(
            label: Text(label),
            onPressed: () => Navigator.pop(
              ctx,
              DateTime.now().subtract(back),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('改入車時間', style: RType.titleSm()),
                const SizedBox(height: 6),
                Text(
                  '落車先記得開計時好常見。計時同預估會跟新時間。',
                  style: RType.muted(),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    chip('早 15 分', const Duration(minutes: 15)),
                    chip('早 30 分', const Duration(minutes: 30)),
                    chip('早 1 小時', const Duration(hours: 1)),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: UberColors.white,
                      side: BorderSide(color: UberColors.hairline),
                    ),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(current),
                      );
                      if (!ctx.mounted || t == null) return;
                      Navigator.pop(
                        ctx,
                        sessionStartFromClock(t.hour, t.minute),
                      );
                    },
                    child: const Text('揀入車時間'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    await context.read<SessionCubit>().adjustStartedAt(picked);
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
                    TextButton(
                      onPressed: _discard,
                      child: Text('取消', style: RType.muted()),
                    ),
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
                      GestureDetector(
                        onTap: () => _editStart(started),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(startLabel, style: RType.muted()),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: UberColors.muted,
                            ),
                          ],
                        ),
                      ),
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
                      const SizedBox(height: 16),
                      _SessionAlarmCard(
                        sessionId: active.id,
                        startedAt: started,
                        parkName: name,
                        hourlyHkd: hourly,
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

class _SessionAlarmCard extends StatelessWidget {
  const _SessionAlarmCard({
    required this.sessionId,
    required this.startedAt,
    required this.parkName,
    this.hourlyHkd,
  });

  final String sessionId;
  final DateTime startedAt;
  final String parkName;
  final double? hourlyHkd;

  static const _presets = <(Duration, String)>[
    (Duration(minutes: 30), '30分'),
    (Duration(hours: 1), '1小時'),
    (Duration(hours: 2), '2小時'),
    (Duration(hours: 3), '3小時'),
  ];

  String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      buildWhen: (prev, next) =>
          prev.alarmAt != next.alarmAt ||
          prev.alarmSessionId != next.alarmSessionId ||
          prev.alarmBusy != next.alarmBusy,
      builder: (context, state) {
        final when = state.alarmFor(sessionId);
        final busy = state.alarmBusy;
        final until = when?.difference(startedAt);
        final fee =
            until == null ? null : estimateParkingFee(until, hourlyHkd);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: UberColors.elevated,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: UberColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('鬧鐘提醒', style: RType.body()),
              const SizedBox(height: 4),
              Text(
                '時間到會响 · 睇下泊咗幾耐、大約幾錢',
                style: RType.muted(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _presets)
                    _chip(
                      label: p.$2,
                      selected: when != null &&
                          (when.difference(DateTime.now()) - p.$1)
                                  .inSeconds
                                  .abs() <
                              90,
                      onTap: busy
                          ? null
                          : () async {
                              final ok = await context
                                  .read<SessionCubit>()
                                  .scheduleAlarm(
                                    after: p.$1,
                                    hourlyHkd: hourlyHkd,
                                    parkName: parkName,
                                  );
                              if (!context.mounted) return;
                              if (!ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('開通知權限先用到鬧鐘'),
                                  ),
                                );
                              }
                            },
                    ),
                ],
              ),
              if (when != null) ...[
                const SizedBox(height: 12),
                Text(
                  fee == null
                      ? '會喺 ${_hhmm(when)} 响 · 到時約泊 ${formatAlarmDuration(until!)}'
                      : '會喺 ${_hhmm(when)} 响 · 到時約泊 ${formatAlarmDuration(until!)} · 預估 HK\$${fee.round()}',
                  style: RType.muted(),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => context.read<SessionCubit>().cancelAlarm(),
                  child: Text('取消鬧鐘', style: RType.body()),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? UberColors.accent.withValues(alpha: 0.18)
              : UberColors.sheet,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? UberColors.accent : UberColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: RType.label().copyWith(
            color: selected ? UberColors.accent : UberColors.white,
          ),
        ),
      ),
    );
  }
}
