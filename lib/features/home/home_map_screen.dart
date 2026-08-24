import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/widgets/slide_to_unlock.dart';
import 'package:recordo/features/home/park_map.dart';
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
  final _mapKey = GlobalKey<ParkMapState>();
  final _sheetCtrl = DraggableScrollableController();
  double _sheetExtent = 0.42;
  bool _locating = false;

  static const _sheetMin = 0.20;
  static const _sheetInit = 0.42;
  static const _sheetMax = 0.88;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<SessionCubit>().state.active != null) {
        setState(() {});
      }
    });
    _sheetCtrl.addListener(_onSheet);
  }

  void _onSheet() {
    if (!_sheetCtrl.isAttached) return;
    final s = _sheetCtrl.size;
    if ((s - _sheetExtent).abs() > 0.008) {
      setState(() => _sheetExtent = s);
    }
  }

  @override
  void dispose() {
    _sheetCtrl.removeListener(_onSheet);
    _sheetCtrl.dispose();
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;

    return Scaffold(
      body: BlocBuilder<ParkCatalogCubit, ParkCatalogState>(
        builder: (context, catalog) {
          return BlocBuilder<SessionCubit, SessionState>(
            builder: (context, session) {
              final active = session.active;
              final selected = catalog.selected;
              // Locate FAB sits just above sheet top
              final sheetH = screenH * _sheetExtent;
              final locateBottom = sheetH + 12;

              return Stack(
                fit: StackFit.expand,
                children: [
                  ParkMap(
                    key: _mapKey,
                    parks: catalog.parks,
                    selectedId: catalog.selectedId,
                    onSelect: (id) =>
                        context.read<ParkCatalogCubit>().select(id),
                    onUserLocation: (ll) => context
                        .read<ParkCatalogCubit>()
                        .setUserLocation(ll.latitude, ll.longitude),
                    onPinMoved: (ll) => context
                        .read<ParkCatalogCubit>()
                        .setPin(ll.latitude, ll.longitude),
                    onLocateState: (locating, err) {
                      if (!mounted) return;
                      setState(() => _locating = locating);
                      if (err != null && err.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err)),
                        );
                      }
                    },
                  ),
                  // Top floating search (Maps-style) + history
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Material(
                              color: UberColors.sheet.withValues(alpha: 0.94),
                              elevation: 6,
                              shadowColor: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                              child: TextField(
                                onChanged: (v) => context
                                    .read<ParkCatalogCubit>()
                                    .setQuery(v),
                                style: RType.body(),
                                cursorColor: UberColors.white,
                                decoration: InputDecoration(
                                  hintText: '搜尋停車場 / 地區',
                                  hintStyle: RType.muted(),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    color: UberColors.muted,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
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
                      top: MediaQuery.paddingOf(context).top + 72,
                      left: 16,
                      right: 16,
                      child: _LiveSessionBanner(
                        label: _fmtDuration(active.elapsed),
                        parkName: active.parkName ?? selected?.name,
                      ),
                    ),
                  // Locate — always above sheet
                  Positioned(
                    right: 16,
                    bottom: locateBottom,
                    child: Material(
                      color: UberColors.sheet.withValues(alpha: 0.95),
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _locating
                            ? null
                            : () => _mapKey.currentState
                                ?.locate(forceCamera: true),
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
                  ),
                  // Draggable bottom sheet
                  NotificationListener<DraggableScrollableNotification>(
                    onNotification: (n) {
                      if ((n.extent - _sheetExtent).abs() > 0.005) {
                        setState(() => _sheetExtent = n.extent);
                      }
                      return false;
                    },
                    child: DraggableScrollableSheet(
                      controller: _sheetCtrl,
                      initialChildSize: _sheetInit,
                      minChildSize: _sheetMin,
                      maxChildSize: _sheetMax,
                      snap: true,
                      snapSizes: const [_sheetMin, _sheetInit, 0.65, _sheetMax],
                      builder: (context, scrollController) {
                        return Material(
                          color: UberColors.sheet,
                          elevation: 12,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              // drag handle
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {},
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 10, 0, 4),
                                  child: Center(
                                    child: Container(
                                      width: 40,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: UberColors.hairline,
                                        borderRadius:
                                            BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // sticky title
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 4, 20, 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        active == null ? '附近停車場' : '泊緊',
                                        style: RType.title(),
                                        textHeightBehavior:
                                            const TextHeightBehavior(
                                          applyHeightToFirstAscent: false,
                                          applyHeightToLastDescent: false,
                                        ),
                                      ),
                                    ),
                                    if (active != null)
                                      Text(
                                        '本月 HK\$${session.monthTotal.toStringAsFixed(0)}',
                                        style: RType.muted(),
                                      )
                                    else
                                      Text(
                                        '${catalog.parks.length} 個',
                                        style: RType.muted(),
                                      ),
                                  ],
                                ),
                              ),
                              // scrollable parks only
                              Expanded(
                                child: ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 8),
                                  itemCount: catalog.parks.length,
                                  itemBuilder: (context, i) {
                                    final p = catalog.parks[i];
                                    final on = p.id == catalog.selectedId;
                                    final dm = context
                                        .read<ParkCatalogCubit>()
                                        .distanceMeters(p);
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: _ParkTile(
                                        park: p,
                                        selected: on,
                                        distance:
                                            ParkCatalogCubit.formatDistance(
                                                dm),
                                        onTap: () => context
                                            .read<ParkCatalogCubit>()
                                            .select(p.id),
                                        onOpenDetail: () =>
                                            context.push('/park/${p.id}'),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // sticky CTA — always visible
                              Material(
                                color: UberColors.sheet,
                                elevation: 8,
                                shadowColor: Colors.black54,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    10,
                                    16,
                                    10 + bottomInset,
                                  ),
                                  child: active == null
                                      ? SlideToUnlock(
                                          label: catalog.selected == null
                                              ? '先揀一個場 · 右滑開始'
                                              : '右滑開始計時',
                                          accent: UberColors.white,
                                          thumbColor: UberColors.black,
                                          enabled:
                                              catalog.selected != null,
                                          onCompleted: () async {
                                            final p = catalog.selected;
                                            if (p == null) return;
                                            await context
                                                .read<SessionCubit>()
                                                .start(
                                                  parkId: p.id,
                                                  parkName: p.name,
                                                );
                                            HapticFeedback.heavyImpact();
                                          },
                                        )
                                      : SlideToUnlock(
                                          label: '右滑結束 · 填收費',
                                          accent: UberColors.accent,
                                          thumbColor: UberColors.black,
                                          trackColor:
                                              const Color(0xFF0A2A1A),
                                          onCompleted: () =>
                                              _endSession(context),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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

class _ParkTile extends StatelessWidget {
  const _ParkTile({
    required this.park,
    required this.selected,
    required this.onTap,
    required this.onOpenDetail,
    this.distance = '',
  });

  final Park park;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;
  final String distance;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? UberColors.elevated2 : UberColors.elevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.local_parking_rounded,
                color: selected ? UberColors.accent : UberColors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(park.name, style: RType.body()),
                    Text(
                      [
                        if (distance.isNotEmpty) distance,
                        park.district,
                        park.priceSummary,
                        if (selected) park.freshnessLabel,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: RType.muted(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!park.hasPrice)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '未有價',
                    style: RType.label().copyWith(color: UberColors.accent),
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '詳情',
                onPressed: onOpenDetail,
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: UberColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
