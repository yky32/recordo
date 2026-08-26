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
  final _mapKey = GlobalKey<ParkMapState>();
  final _searchKey = GlobalKey();
  final _sheetKey = GlobalKey();
  final _sheetCtrl = DraggableScrollableController();
  /// Keys so map pin select can [Scrollable.ensureVisible] the list row.
  final _itemKeys = <String, GlobalKey>{};

  /// Avoid setState during sheet drag — full rebuild kills list scroll.
  final _sheetExtent = ValueNotifier<double>(_sheetInit);
  final _bandTopY = ValueNotifier<double>(120);
  final _bandBottomY = ValueNotifier<double>(500);
  bool _locating = false;

  static const _sheetMin = 0.28;
  static const _sheetMinWithCta = 0.38;
  static const _sheetInit = 0.42;
  static const _sheetMax = 0.88;

  @override
  void initState() {
    super.initState();
    _sheetCtrl.addListener(_onSheet);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureChrome());
  }

  void _onSheet() {
    if (!_sheetCtrl.isAttached) return;
    final s = _sheetCtrl.size;
    if ((s - _sheetExtent.value).abs() <= 0.008) return;
    // Never notify during build (DSS fires while tree builds).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetCtrl.isAttached) return;
      final v = _sheetCtrl.size;
      if ((v - _sheetExtent.value).abs() > 0.008) {
        _sheetExtent.value = v;
      }
      _measureChrome();
    });
  }

  /// [applyNow] = update band notifiers immediately (call outside build only).
  ({double top, double bottom}) _readBand({bool applyNow = false}) {
    final h = MediaQuery.sizeOf(context).height;
    var topY = h * 0.14;
    var bottomY = h * (1.0 - _sheetExtent.value);

    final searchBox =
        _searchKey.currentContext?.findRenderObject() as RenderBox?;
    if (searchBox != null && searchBox.hasSize) {
      final origin = searchBox.localToGlobal(Offset.zero);
      topY = origin.dy + searchBox.size.height;
    }

    final sheetBox = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
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

    if ((topY - _bandTopY.value).abs() > 0.5 ||
        (bottomY - _bandBottomY.value).abs() > 0.5) {
      if (applyNow) {
        _bandTopY.value = topY;
        _bandBottomY.value = bottomY;
      } else {
        final t = topY;
        final b = bottomY;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if ((t - _bandTopY.value).abs() > 0.5) _bandTopY.value = t;
          if ((b - _bandBottomY.value).abs() > 0.5) _bandBottomY.value = b;
        });
      }
    }
    return (top: topY, bottom: bottomY);
  }

  void _measureChrome() {
    if (!mounted) return;
    _readBand();
  }

  GlobalKey _keyForPark(String id) =>
      _itemKeys.putIfAbsent(id, GlobalKey.new);

  /// Select park + list anchor + keep map pin above sheet (not under lip).
  Future<void> _selectAndAnchor(String id, List<Park> parks) async {
    if (!mounted) return;
    final cubit = context.read<ParkCatalogCubit>();
    cubit.select(id);

    // Leave more map than 0.65 — pin was almost covered by sheet
    const targetSheet = 0.52;
    if (_sheetCtrl.isAttached && _sheetCtrl.size < targetSheet - 0.02) {
      try {
        await _sheetCtrl.animateTo(
          targetSheet.clamp(_sheetMinWithCta, _sheetMax),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    }

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    // After sheet moves: refresh band + recenter pin into visible map
    if (_sheetCtrl.isAttached) {
      _sheetExtent.value = _sheetCtrl.size;
    }
    _readBand(applyNow: true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    _mapKey.currentState?.centerOnSelected();

    final ctx = _keyForPark(id).currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ctx2 = _keyForPark(id).currentContext;
      if (ctx2 != null) {
        await Scrollable.ensureVisible(
          ctx2,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.12,
        );
      }
    });
  }

  @override
  void dispose() {
    _sheetCtrl.removeListener(_onSheet);
    _sheetCtrl.dispose();
    _sheetExtent.dispose();
    _bandTopY.dispose();
    _bandBottomY.dispose();
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
            buildWhen: (prev, next) =>
                prev.active?.id != next.active?.id ||
                prev.history.length != next.history.length,
            builder: (context, session) {
              final active = session.active;
              final selected = catalog.selected;
              final showCta = active != null || selected != null;
              final sheetMin = showCta ? _sheetMinWithCta : _sheetMin;

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
                  ListenableBuilder(
                    listenable: Listenable.merge([_bandTopY, _bandBottomY]),
                    builder: (context, _) {
                      return ParkMap(
                        key: _mapKey,
                        parks: catalog.parks,
                        selectedId: catalog.selectedId,
                        bandTopY: _bandTopY.value,
                        bandBottomY: _bandBottomY.value,
                        onSelect: (id) {
                          hideKeyboard();
                          _selectAndAnchor(id, catalog.parks);
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
                      );
                    },
                  ),
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
                        child: _LiveSessionTicker(
                          parkName: active.parkName ?? selected?.name,
                          startedAt: active.startedAt,
                        ),
                      ),
                    ),
                  // Locate FAB — only this listens to sheet height
                  ValueListenableBuilder<double>(
                    valueListenable: _sheetExtent,
                    builder: (context, extent, _) {
                      return Positioned(
                        right: 16,
                        bottom: screenH * extent + 12,
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
                                    _readBand();
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      _mapKey.currentState?.centerOnMe();
                                    });
                                  },
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: _locating
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      Icons.my_location_rounded,
                                      color: UberColors.white,
                                    ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  NotificationListener<DraggableScrollableNotification>(
                    onNotification: (n) {
                      // Defer — DSS notifies during build; never markNeedsBuild mid-build.
                      final extent = n.extent;
                      if ((extent - _sheetExtent.value).abs() > 0.005) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if ((extent - _sheetExtent.value).abs() > 0.005) {
                            _sheetExtent.value = extent;
                          }
                          _measureChrome();
                        });
                      }
                      return false;
                    },
                    child: DraggableScrollableSheet(
                      controller: _sheetCtrl,
                      initialChildSize: _sheetInit,
                      minChildSize: sheetMin,
                      maxChildSize: _sheetMax,
                      snap: false, // drag free — stop at release height
                      builder: (context, scrollController) {
                        final showCtaBar =
                            active != null || selected != null;
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
                          child: Column(
                            children: [
                              const SizedBox(height: 10),
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 5,
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: UberColors.hairline,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        active == null ? '附近停車場' : '泊緊',
                                        style: RType.titleSm(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      active != null
                                          ? '本月 HK\$${session.monthTotal.toStringAsFixed(0)}'
                                          : catalog.totalInDb > 0
                                              ? '${catalog.parks.length} 附近 · 庫存 ${catalog.totalInDb}'
                                              : '${catalog.parks.length} 個',
                                      style: RType.muted(),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Stack(
                                  children: [
                                    ListView.builder(
                                      controller: scrollController,
                                      primary: false,
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        ctaPad,
                                      ),
                                      physics:
                                          const AlwaysScrollableScrollPhysics(
                                        parent: BouncingScrollPhysics(),
                                      ),
                                      itemCount: catalog.parks.length,
                                      itemBuilder: (context, i) {
                                        final park = catalog.parks[i];
                                        final on =
                                            park.id == catalog.selectedId;
                                        final dm = context
                                            .read<ParkCatalogCubit>()
                                            .distanceMeters(park);
                                        return Padding(
                                          key: _keyForPark(park.id),
                                          padding: const EdgeInsets.only(
                                              bottom: 8),
                                          child: _ParkTile(
                                            park: park,
                                            selected: on,
                                            distance: ParkCatalogCubit
                                                .formatDistance(dm),
                                            onTap: () => _selectAndAnchor(
                                              park.id,
                                              catalog.parks,
                                            ),
                                            onOpenDetail: () => context.push(
                                              parkDetailLocation(park.id),
                                            ),
                                          ),
                                        );
                                      },
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
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Text(
                                                        selected!.name,
                                                        style: RType.body(),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      const SizedBox(height: 6),
                                                      SlideToUnlock(
                                                        label: '右滑開始計時',
                                                        height: 56,
                                                        accent:
                                                            UberColors.ctaFill,
                                                        thumbColor: UberColors
                                                            .ctaOnFill,
                                                        onCompleted: () async {
                                                          final park = catalog
                                                              .selected;
                                                          if (park == null) {
                                                            return;
                                                          }
                                                          final hourly =
                                                              park.hourlyHkd;
                                                          await context
                                                              .read<
                                                                  SessionCubit>()
                                                              .start(
                                                                parkId: park.id,
                                                                parkName:
                                                                    park.name,
                                                                hourlyLabel:
                                                                    hourly !=
                                                                            null
                                                                        ? 'HK\$${hourly.toStringAsFixed(0)}'
                                                                        : null,
                                                              );
                                                          HapticFeedback
                                                              .heavyImpact();
                                                          if (context.mounted) {
                                                            context.push(
                                                                '/session');
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  )
                                                : SlideToUnlock(
                                                    label: '右滑結束 · 填收費',
                                                    height: 56,
                                                    accent: UberColors.accent,
                                                    thumbColor:
                                                        UberColors.ctaOnFill,
                                                    trackColor:
                                                        ThemeController
                                                                .instance
                                                                .isDark
                                                            ? const Color(
                                                                0xFF0A2A1A)
                                                            : const Color(
                                                                0xFFD4F5E4),
                                                    onCompleted: () =>
                                                        _endSession(context),
                                                  ),
                                          ),
                                        ),
                                      ),
                                  ],
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
}

/// Isolated ticker so session clock doesn't rebuild sheet/list.
class _LiveSessionTicker extends StatefulWidget {
  const _LiveSessionTicker({required this.startedAt, this.parkName});
  final DateTime startedAt;
  final String? parkName;

  @override
  State<_LiveSessionTicker> createState() => _LiveSessionTickerState();
}

class _LiveSessionTickerState extends State<_LiveSessionTicker> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '計時中',
                  style: RType.label().copyWith(
                    color: UberColors.accent,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  widget.parkName ?? '未選場',
                  style: RType.body(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(_fmt(elapsed), style: RType.titleSm()),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: UberColors.muted, size: 22),
        ],
      ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? UberColors.accent.withValues(alpha: 0.35)
              : UberColors.hairline,
        ),
      ),
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
