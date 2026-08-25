import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:recordo/app/routes.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/core/widgets/slide_to_unlock.dart';
import 'package:recordo/features/home/park_map.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/end_session_sheet.dart';
import 'package:recordo/features/session/session_cubit.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  Timer? _tick;
  final _mapKey = GlobalKey<ParkMapState>();
  final _searchKey = GlobalKey();
  final _sheetKey = GlobalKey();
  final _sheetCtrl = DraggableScrollableController();
  double _sheetExtent = 0.42;
  bool _locating = false;
  double _bandTopY = 120;
  double _bandBottomY = 500;

  static const _sheetMin = 0.28; // header only
  static const _sheetMinWithCta = 0.38; // header + slide CTA + safe area
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureChrome());
  }

  void _onSheet() {
    if (!_sheetCtrl.isAttached) return;
    final s = _sheetCtrl.size;
    if ((s - _sheetExtent).abs() > 0.008) {
      setState(() => _sheetExtent = s);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureChrome());
    }
  }

  /// Dynamic: search bar bottom Y + sheet top Y (the two red lines).
  /// Returns live values (also updates state when changed).
  ({double top, double bottom}) _readBand() {
    final h = MediaQuery.sizeOf(context).height;
    var topY = h * 0.14;
    var bottomY = h * (1.0 - _sheetExtent);

    final searchBox =
        _searchKey.currentContext?.findRenderObject() as RenderBox?;
    if (searchBox != null && searchBox.hasSize) {
      final origin = searchBox.localToGlobal(Offset.zero);
      topY = origin.dy + searchBox.size.height;
    }

    final sheetBox =
        _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (sheetBox != null && sheetBox.hasSize) {
      bottomY = sheetBox.localToGlobal(Offset.zero).dy;
    } else if (_sheetCtrl.isAttached) {
      bottomY = h * (1.0 - _sheetCtrl.size);
    }

    if (!topY.isFinite || topY < 0) topY = h * 0.14;
    if (!bottomY.isFinite) bottomY = h * 0.55;
    if (topY > h) topY = h * 0.14;
    if (bottomY > h) bottomY = h;
    if (bottomY < topY + 100) {
      // Prefer real sheet fraction so mid stays honest when sheet is tall
      if (_sheetCtrl.isAttached) {
        bottomY = h * (1.0 - _sheetCtrl.size);
      }
      if (bottomY < topY + 100) {
        bottomY = (topY + (h - topY) * 0.45).clamp(0.0, h);
      }
    }
    if (bottomY <= topY) {
      topY = h * 0.12;
      bottomY = h * 0.55;
    }

    if ((topY - _bandTopY).abs() > 0.5 ||
        (bottomY - _bandBottomY).abs() > 0.5) {
      // Defer setState — callers may be in build/frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if ((topY - _bandTopY).abs() > 0.5 ||
            (bottomY - _bandBottomY).abs() > 0.5) {
          setState(() {
            _bandTopY = topY;
            _bandBottomY = bottomY;
          });
        }
      });
    }
    return (top: topY, bottom: bottomY);
  }

  void _measureChrome() {
      if (!mounted) return;
      _readBand();
    }

    Future<void> _endSession(BuildContext context) async {
  void dispose() {
    _sheetCtrl.removeListener(_onSheet);
    _sheetCtrl.dispose();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _endSession(BuildContext context) async {
    await showEndSessionSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: BlocBuilder<ParkCatalogCubit, ParkCatalogState>(
        builder: (context, catalog) {
          return BlocBuilder<SessionCubit, SessionState>(
            builder: (context, session) {
              final active = session.active;
              final selected = catalog.selected;
              final showCta = active != null || selected != null;
              final sheetMin = showCta ? _sheetMinWithCta : _sheetMin;
              // Locate FAB sits just above sheet top
              final sheetH = screenH * _sheetExtent;
              final locateBottom = sheetH + 12;

              // Keep sheet tall enough for sticky CTA (avoids Column overflow)
              if (showCta &&
                  _sheetCtrl.isAttached &&
                  _sheetCtrl.size + 0.001 < sheetMin) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_sheetCtrl.isAttached) return;
                  if (_sheetCtrl.size < sheetMin) {
                    _sheetCtrl.jumpTo(sheetMin);
                  }
                });
              }

              void hideKeyboard() {
                FocusManager.instance.primaryFocus?.unfocus();
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Full-screen map (tiles need stable non-zero size)
                  ParkMap(
                    key: _mapKey,
                    parks: catalog.parks,
                    selectedId: catalog.selectedId,
                    bandTopY: _bandTopY,
                    bandBottomY: _bandBottomY,
                    onSelect: (id) {
                      hideKeyboard();
                      context.read<ParkCatalogCubit>().select(id);
                    },
                    onMapInteraction: hideKeyboard,
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
                        key: _searchKey,
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
                                onTapOutside: (_) => hideKeyboard(),
                                style: RType.body(),
                                cursorColor: UberColors.white,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => hideKeyboard(),
                                decoration: InputDecoration(
                                  hintText: '搜尋停車場 / 地區',
                                  hintStyle: RType.muted(),
                                  prefixIcon: Icon(
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
                            onTap: () {
                              hideKeyboard();
                              context.push('/history');
                            },
                          ),
                          const SizedBox(width: 8),
                          _RoundIcon(
                            icon: Icons.settings_rounded,
                            onTap: () {
                              hideKeyboard();
                              context.push('/settings');
                            },
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
                      child: GestureDetector(
                        onTap: () => context.push('/session'),
                        child: _LiveSessionBanner(
                          label: formatSessionDuration(active.elapsed),
                          parkName: active.parkName ?? selected?.name,
                        ),
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
                            : () {
                                hideKeyboard();
                                final band = _readBand();
                                setState(() {
                                  _bandTopY = band.top;
                                  _bandBottomY = band.bottom;
                                });
                                // After layout settles map size, center
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  _mapKey.currentState?.centerOnMe();
                                });
                              },
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: _locating
                              ? Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: UberColors.white,
                                  ),
                                )
                              : Icon(
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
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _measureChrome());
                      }
                      return false;
                    },
                    child: DraggableScrollableSheet(
                      controller: _sheetCtrl,
                      initialChildSize: _sheetInit,
                      minChildSize: sheetMin,
                      maxChildSize: _sheetMax,
                      snap: true,
                      snapSizes: [
                        sheetMin,
                        _sheetInit,
                        0.65,
                        _sheetMax,
                      ],
                      builder: (context, scrollController) {
                        final showCtaBar = active != null || selected != null;
                        // Approximate sticky footer height for list bottom padding
                        final ctaPad = showCtaBar
                            ? (active == null ? 120.0 : 80.0) + bottomInset
                            : 12.0 + bottomInset;

                        return Material(
                          key: _sheetKey,
                          color: UberColors.sheet,
                          elevation: 12,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          clipBehavior: Clip.antiAlias,
                          // ONE scroll view + DSS controller = list scrolls + sheet drag.
                          // Column+Expanded+ListView broke vertical drag competition.
                          child: Stack(
                            children: [
                              CustomScrollView(
                                controller: scrollController,
                                physics: const ClampingScrollPhysics(),
                                slivers: [
                                  SliverToBoxAdapter(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => FocusManager
                                          .instance.primaryFocus
                                          ?.unfocus(),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                0, 10, 0, 6),
                                            child: Center(
                                              child: Container(
                                                width: 44,
                                                height: 5,
                                                decoration: BoxDecoration(
                                                  color: UberColors.hairline,
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                20, 0, 20, 8),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    active == null
                                                        ? '附近停車場'
                                                        : '泊緊',
                                                    style: RType.titleSm(),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
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
                                                    catalog.totalInDb > 0
                                                        ? '${catalog.parks.length} 附近 · 庫存 ${catalog.totalInDb}'
                                                        : '${catalog.parks.length} 個',
                                                    style: RType.muted(),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      ctaPad,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, i) {
                                          final p = catalog.parks[i];
                                          final on =
                                              p.id == catalog.selectedId;
                                          final dm = context
                                              .read<ParkCatalogCubit>()
                                              .distanceMeters(p);
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8),
                                            child: _ParkTile(
                                              park: p,
                                              selected: on,
                                              distance: ParkCatalogCubit
                                                  .formatDistance(dm),
                                              onTap: () => context
                                                  .read<ParkCatalogCubit>()
                                                  .select(p.id),
                                              onOpenDetail: () => context.push(
                                                  parkDetailLocation(p.id)),
                                            ),
                                          );
                                        },
                                        childCount: catalog.parks.length,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (showCtaBar)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Material(
                                    color: UberColors.sheet,
                                    elevation: 8,
                                    shadowColor: Colors.black54,
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        8 + bottomInset,
                                      ),
                                      child: active == null
                                          ? Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  selected!.name,
                                                  style: RType.body(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 6),
                                                SlideToUnlock(
                                                  label: '右滑開始計時',
                                                  height: 56,
                                                  accent: UberColors.ctaFill,
                                                  thumbColor:
                                                      UberColors.ctaOnFill,
                                                  onCompleted: () async {
                                                    final p = catalog.selected;
                                                    if (p == null) return;
                                                    final hourly = p.hourlyHkd;
                                                    await context
                                                        .read<SessionCubit>()
                                                        .start(
                                                          parkId: p.id,
                                                          parkName: p.name,
                                                          hourlyLabel: hourly !=
                                                                  null
                                                              ? 'HK\$${hourly.toStringAsFixed(0)}'
                                                              : null,
                                                        );
                                                    HapticFeedback
                                                        .heavyImpact();
                                                    if (context.mounted) {
                                                      context.push('/session');
                                                    }
                                                  },
                                                ),
                                              ],
                                            )
                                          : SlideToUnlock(
                                              label: '右滑結束 · 填收費',
                                              height: 56,
                                              accent: UberColors.accent,
                                              thumbColor: UberColors.ctaOnFill,
                                              trackColor: ThemeController
                                                      .instance.isDark
                                                  ? const Color(0xFF0A2A1A)
                                                  : const Color(0xFFD4F5E4),
                                              onCompleted: () =>
                                                  _endSession(context),
                                            ),
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


  String formatSessionDuration(Duration d) {
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
            decoration: BoxDecoration(
              color: UberColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 10),
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
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: UberColors.muted, size: 22),
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
              SizedBox(width: 10),
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
                icon: Icon(
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
