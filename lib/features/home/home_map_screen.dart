import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/widgets/slide_to_unlock.dart';
import 'package:recordo/features/home/uber_map_canvas.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/session_cubit.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<SessionCubit>().state.active != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _endSession(BuildContext context) async {
    final session = context.read<SessionCubit>().state.active;
    if (session == null) return;
    final amountCtrl = TextEditingController();
    final catalog = context.read<ParkCatalogCubit>();
    final selected = catalog.state.selected;
    var updatePrice = true;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: UberColors.sheet,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('結束', style: RType.title()),
                  const SizedBox(height: 6),
                  Text(
                    '今次泊咗幾多錢？',
                    style: RType.muted(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: RType.titleSm(),
                    decoration: InputDecoration(
                      prefixText: 'HK\$ ',
                      prefixStyle: RType.titleSm(),
                      hintText: '0',
                      filled: true,
                      fillColor: UberColors.elevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selected != null)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '順便更新場價',
                        style: RType.body(),
                      ),
                      subtitle: null,
                      value: updatePrice,
                      activeThumbColor: UberColors.accent,
                      onChanged: (v) => setModal(() => updatePrice = v),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: UberColors.white,
                      foregroundColor: UberColors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      final v = double.tryParse(amountCtrl.text.trim());
                      if (v == null || v < 0) return;
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('儲存'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok != true || !context.mounted) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final park = catalog.state.selected;
    await context.read<SessionCubit>().end(
          amountHkd: amount,
          parkId: park?.id ?? session.parkId,
          parkName: park?.name ?? session.parkName,
        );
    if (updatePrice && park != null && amount > 0 && context.mounted) {
      // Treat paid amount as a soft hourly signal if session short; else store as note via hourly guess.
      final hours = session.elapsed.inMinutes / 60.0;
      final hourly = hours >= 0.25 ? (amount / hours) : amount;
      await catalog.reportPrice(
        parkId: park.id,
        hourly: double.parse(hourly.toStringAsFixed(0)),
      );
    }
    if (context.mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已記低')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: BlocBuilder<ParkCatalogCubit, ParkCatalogState>(
        builder: (context, catalog) {
          return BlocBuilder<SessionCubit, SessionState>(
            builder: (context, session) {
              final active = session.active;
              final selected = catalog.selected;

              return Stack(
                fit: StackFit.expand,
                children: [
                  UberMapCanvas(
                    parks: catalog.parks,
                    selectedId: catalog.selectedId,
                    onSelect: (id) =>
                        context.read<ParkCatalogCubit>().select(id),
                  ),
                  // top chrome
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          _Pill(
                            child: Text('Recordo', style: RType.titleSm()),
                          ),
                          const Spacer(),
                          _RoundIcon(
                            icon: Icons.receipt_long_rounded,
                            onTap: () => context.push('/history'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (active != null)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 64,
                      left: 16,
                      right: 16,
                      child: _LiveSessionBanner(
                        label: _fmtDuration(active.elapsed),
                        parkName: active.parkName ?? selected?.name,
                      ),
                    ),
                  // bottom sheet-ish panel
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.52,
                      ),
                      decoration: const BoxDecoration(
                        color: UberColors.sheet,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 24,
                            offset: Offset(0, -8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: UberColors.hairline,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    active == null
                                        ? '附近停車場'
                                        : '泊緊',
                                    style: RType.title(),
                                    // Syne g/y/p need room; avoid parent clip.
                                    textHeightBehavior:
                                        const TextHeightBehavior(
                                      applyHeightToFirstAscent: false,
                                      applyHeightToLastDescent: false,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '本月 HK\$${session.monthTotal.toStringAsFixed(0)}',
                                  style: RType.muted(),
                                ),
                              ],
                            ),
                          ),
                          if (selected != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: _SelectedCard(
                                park: selected,
                                onOpen: () =>
                                    context.push('/park/${selected.id}'),
                              ),
                            ),
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              itemCount: catalog.parks.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final p = catalog.parks[i];
                                final on = p.id == catalog.selectedId;
                                return _ParkTile(
                                  park: p,
                                  selected: on,
                                  onTap: () => context
                                      .read<ParkCatalogCubit>()
                                      .select(p.id),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottom),
                            child: active == null
                                ? SlideToUnlock(
                                    label: '右滑開始計時',
                                    accent: UberColors.white,
                                    thumbColor: UberColors.black,
                                    onCompleted: () async {
                                      final p = catalog.selected;
                                      await context.read<SessionCubit>().start(
                                            parkId: p?.id,
                                            parkName: p?.name,
                                          );
                                      HapticFeedback.heavyImpact();
                                    },
                                  )
                                : SlideToUnlock(
                                    label: '右滑結束 · 填收費',
                                    accent: UberColors.accent,
                                    thumbColor: UberColors.black,
                                    trackColor: const Color(0xFF0A2A1A),
                                    onCompleted: () => _endSession(context),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: UberColors.sheet.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: UberColors.hairline),
      ),
      child: child,
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UberColors.sheet.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: UberColors.white, size: 22),
        ),
      ),
    );
  }
}

class _LiveSessionBanner extends StatelessWidget {
  const _LiveSessionBanner({required this.label, this.parkName});
  final String label;
  final String? parkName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: UberColors.elevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: UberColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: UberColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('計時中', style: RType.label().copyWith(
                  color: UberColors.accent,
                  letterSpacing: 1.2,
                )),
                Text(
                  parkName ?? '未選場',
                  style: RType.body(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(label, style: RType.titleSm()),
        ],
      ),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.park, required this.onOpen});
  final Park park;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UberColors.elevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(park.name, style: RType.titleSm()),
                    const SizedBox(height: 4),
                    Text(
                      '${park.priceSummary} · ${park.freshnessLabel}',
                      style: RType.muted(),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: UberColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParkTile extends StatelessWidget {
  const _ParkTile({
    required this.park,
    required this.selected,
    required this.onTap,
  });

  final Park park;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? UberColors.elevated2 : UberColors.elevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.local_parking_rounded,
                color: selected ? UberColors.accent : UberColors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(park.name, style: RType.body()),
                    Text(
                      '${park.district} · ${park.priceSummary}',
                      style: RType.muted(),
                    ),
                  ],
                ),
              ),
              if (!park.hasPrice)
                Text('未有價', style: RType.label().copyWith(
                  color: UberColors.accent,
                )),
            ],
          ),
        ),
      ),
    );
  }
}
