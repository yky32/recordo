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
import 'package:recordo/features/home/wedge_onboarding.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/end_session_sheet.dart';
import 'package:recordo/features/session/session_cubit.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with SingleTickerProviderStateMixin {
  final _mapKey = GlobalKey<ParkMapState>();
  final _searchKey = GlobalKey();
  final _sheetKey = GlobalKey();
  /// Keys so map pin select can [Scrollable.ensureVisible] the list row.
  final _itemKeys = <String, GlobalKey>{};
  final _listScroll = ScrollController();
  final _searchCtrl = TextEditingController();

  /// Sheet height as a fraction of screen. Only the handle drags this.
  final _sheetExtent = ValueNotifier<double>(_sheetInit);
  final _bandTopY = ValueNotifier<double>(120);
  final _bandBottomY = ValueNotifier<double>(500);
  bool _locating = false;
  String? _meterId;
  AnimationController? _sheetAnim;

  static const _sheetMin = 0.28;
  static const _sheetMinWithCta = 0.38;
  static const _sheetInit = 0.42;
  static const _sheetMax = 0.88;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureChrome();
      if (mounted) showWedgeExplainerIfNeeded(context);
    });
  }

  void _setSheetExtent(double value, double min) {
    final next = value.clamp(min, _sheetMax);
    if ((next - _sheetExtent.value).abs() < 0.0008) return;
    _sheetExtent.value = next;
  }

  void _onHandleDragUpdate(DragUpdateDetails d, double min) {
    _sheetAnim?.stop();
    final h = MediaQuery.sizeOf(context).height;
    _setSheetExtent(_sheetExtent.value - d.delta.dy / h, min);
  }

  void _onHandleDragEnd(DragEndDetails d, double min) {
    final v = d.velocity.pixelsPerSecond.dy;
    if (v.abs() < 450) {
      _measureChrome();
      return;
    }
    final target = v < 0 ? _sheetMax : min;
    _animateSheetTo(target, min);
  }

  Future<void> _animateSheetTo(double target, double min) async {
    final to = target.clamp(min, _sheetMax);
    final from = _sheetExtent.value;
    if ((to - from).abs() < 0.01) return;
    _sheetAnim?.stop();
    _sheetAnim?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _sheetAnim = ctrl;
    final anim = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic),
    );
    anim.addListener(() {
      if (!mounted) return;
      _sheetExtent.value = anim.value;
    });
    try {
      await ctrl.forward();
    } catch (_) {}
    if (mounted) _measureChrome();
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
    } else {
      bottomY = h * (1.0 - _sheetExtent.value);
    }

    if (!topY.isFinite || topY < 0) topY = h * 0.14;
    if (!bottomY.isFinite) bottomY = h * 0.55;
    if (topY > h) topY = h * 0.14;
    if (bottomY > h) bottomY = h;
    if (bottomY < topY + 100) {
      bottomY = h * (1.0 - _sheetExtent.value);
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
    cubit.selectFromMap(id);

    const targetSheet = 0.52;
    if (_sheetExtent.value < targetSheet - 0.02) {
      await _animateSheetTo(
        targetSheet.clamp(_sheetMinWithCta, _sheetMax),
        _sheetMinWithCta,
      );
    }

    await _afterFrames(2);
    if (!mounted) return;

    _readBand(applyNow: true);
    await _afterFrames(1);
    if (!mounted) return;
    _mapKey.currentState?.centerOnSelected();

    await _scrollListToPark(cubit.state, id);
    if (!mounted) return;
    await _ensureParkRowVisible(id);
  }

  Future<void> _afterFrames(int count) async {
    for (var i = 0; i < count; i++) {
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _scrollListToPark(ParkCatalogState catalog, String id) async {
    if (!_listScroll.hasClients) return;
    final index = _sheetIndexForPark(catalog, id);
    if (index == null) return;

    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _sheetRowExtent(_sheetEntry(catalog, i));
    }
    final max = _listScroll.position.maxScrollExtent;
    await _listScroll.animateTo(
      offset.clamp(0, max),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _ensureParkRowVisible(String id) async {
    final ctx = _keyForPark(id).currentContext;
    if (ctx == null || !ctx.mounted) {
      await _afterFrames(1);
      if (!mounted) return;
    }
    final target = _keyForPark(id).currentContext;
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  void dispose() {
    _sheetAnim?.dispose();
    _listScroll.dispose();
    _searchCtrl.dispose();
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
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = kb > 8;

    return Scaffold(
      // ClipVal: sheet owns the keyboard. Don't shrink the map.
      resizeToAvoidBottomInset: false,
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

              if (showCta && _sheetExtent.value + 0.001 < sheetMin) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (_sheetExtent.value < sheetMin) {
                    _sheetExtent.value = sheetMin;
                  }
                });
              }

              void hideKeyboard() {
                FocusManager.instance.primaryFocus?.unfocus();
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  ParkMap(
                    key: _mapKey,
                    parks: catalog.allWindowParks,
                    meterSpaces: catalog.meterSpaces,
                    meterOccupancy: catalog.meterOccupancy,
                    selectedId: catalog.selectedId,
                    selectedMeterId: _meterId,
                    bandTopY: _bandTopY,
                    bandBottomY: _bandBottomY,
                    onSelect: (id) {
                      hideKeyboard();
                      setState(() => _meterId = null);
                      _selectAndAnchor(id, catalog.allWindowParks);
                    },
                    onSelectMeter: (id) {
                      hideKeyboard();
                      setState(() => _meterId = id.isEmpty ? null : id);
                    },
                    onMeterViewport: ({
                      required minLat,
                      required minLng,
                      required maxLat,
                      required maxLng,
                      required zoom,
                    }) {
                      context.read<ParkCatalogCubit>().onMeterViewport(
                            minLat: minLat,
                            minLng: minLng,
                            maxLat: maxLat,
                            maxLng: maxLng,
                            zoom: zoom,
                          );
                    },
                    destLat: catalog.destLat,
                    destLng: catalog.destLng,
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
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        key: _searchKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Material(
                                  color: UberColors.sheet
                                      .withValues(alpha: 0.94),
                                  elevation: 6,
                                  shadowColor: Colors.black54,
                                  borderRadius: BorderRadius.circular(16),
                                  child: TextField(
                                controller: _searchCtrl,
                                onChanged: (v) => context
                                    .read<ParkCatalogCubit>()
                                    .setQuery(v),
                                onTapOutside: (_) => hideKeyboard(),
                                style: RType.body(),
                                cursorColor: UberColors.white,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => hideKeyboard(),
                                decoration: InputDecoration(
                                  hintText: '搜尋目的地 / 停車場',
                                  hintStyle: RType.muted(),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: UberColors.muted,
                                  ),
                                  suffixIcon: catalog.query.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: '清除',
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            context
                                                .read<ParkCatalogCubit>()
                                                .setQuery('');
                                          },
                                          icon: Icon(
                                            Icons.close_rounded,
                                            color: UberColors.muted,
                                          ),
                                        ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            if (catalog.destLabel.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '用：${catalog.destLabel}',
                                    style: RType.muted(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
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
                  if (catalog.meterSpaces.isNotEmpty)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top +
                          (active != null ? 128 : 64),
                      left: 12,
                      child: IgnorePointer(
                        child: Row(
                          children: const [
                            _MeterLegendDot(
                              color: Color(0xFF2FA86B),
                              label: '空置',
                            ),
                            SizedBox(width: 8),
                            _MeterLegendDot(
                              color: Color(0xFFE24B4A),
                              label: '已使用',
                            ),
                            SizedBox(width: 8),
                            _MeterLegendDot(
                              color: Color(0xFF8A8A8A),
                              label: '暫停',
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
                        bottom: screenH * extent + 12 + kb,
                        child: Material(
                          color: ThemeController.instance.isDark
                              ? const Color(0xFF1C1C1E)
                              : Colors.white,
                          shape: const CircleBorder(),
                          elevation: 6,
                          shadowColor: Colors.black54,
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
                                  : const Icon(
                                      Icons.my_location_rounded,
                                      color: Color(0xFF4285F4),
                                    ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  ListenableBuilder(
                    listenable: _sheetExtent,
                    child: Material(
                      key: _sheetKey,
                      color: UberColors.sheet,
                      elevation: 12,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _SheetDragHandle(
                            title: active == null ? '附近停車場' : '泊緊',
                            trailing: active != null
                                ? '本月 HK\$${session.monthTotal.toStringAsFixed(0)}'
                                : catalog.isSearching
                                    ? '${catalog.parks.length} 個結果'
                                    : catalog.restParks.isEmpty
                                        ? '${catalog.parks.length} 個附近'
                                        : '${catalog.parks.length} 個有價 · ${catalog.restParks.length} 其他',
                            onUpdate: (d) =>
                                _onHandleDragUpdate(d, sheetMin),
                            onEnd: (d) => _onHandleDragEnd(d, sheetMin),
                          ),
                          Expanded(
                            child: Stack(
                              children: [
                                ListView.builder(
                                  controller: _listScroll,
                                  primary: false,
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    keyboardOpen
                                        ? 12.0 + kb
                                        : ((active != null ||
                                                    selected != null)
                                                ? (active == null
                                                    ? 120.0
                                                    : 80.0)
                                                : 12.0) +
                                            bottomInset,
                                  ),
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  itemCount: _sheetItemCount(catalog),
                                  itemBuilder: (context, i) {
                                    final entry = _sheetEntry(catalog, i);
                                    if (entry.isHeader) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Material(
                                          color: UberColors.elevated,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            onTap: () => context
                                                .read<ParkCatalogCubit>()
                                                .toggleRestParks(),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 12,
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      catalog.showRestParks
                                                          ? '收起其他停車位'
                                                          : '顯示其他停車位（${catalog.restParks.length}）',
                                                      style: RType.body(),
                                                    ),
                                                  ),
                                                  Icon(
                                                    catalog.showRestParks
                                                        ? Icons
                                                            .expand_less_rounded
                                                        : Icons
                                                            .expand_more_rounded,
                                                    color: UberColors.muted,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    final park = entry.park!;
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
                                        vacancy: catalog
                                            .tdVacancyFor(park.id)
                                            ?.label,
                                        onTap: () => _selectAndAnchor(
                                          park.id,
                                          catalog.allWindowParks,
                                        ),
                                        onOpenDetail: () => context.push(
                                          parkDetailLocation(park.id),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (!keyboardOpen &&
                                    (active != null || selected != null))
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
                    ),
                    builder: (context, child) {
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          height: screenH * _sheetExtent.value + kb,
                          width: double.infinity,
                          child: child,
                        ),
                      );
                    },
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

/// Handle + title row. This is the only surface that resizes the sheet.
class _SheetDragHandle extends StatelessWidget {
  const _SheetDragHandle({
    required this.title,
    required this.trailing,
    required this.onUpdate,
    required this.onEnd,
  });

  final String title;
  final String trailing;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onUpdate,
      onVerticalDragEnd: onEnd,
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: RType.titleSm(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(trailing, style: RType.muted()),
              ],
            ),
          ),
        ],
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

class _MeterLegendDot extends StatelessWidget {
  const _MeterLegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: UberColors.sheet.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: RType.muted()),
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

class _SheetEntry {
  const _SheetEntry.header() : park = null, isHeader = true;
  const _SheetEntry.park(this.park) : isHeader = false;
  final Park? park;
  final bool isHeader;
}

int _sheetItemCount(ParkCatalogState catalog) {
  final featured = catalog.parks.length;
  if (catalog.isSearching || catalog.restParks.isEmpty) {
    return featured;
  }
  final header = 1;
  final rest = catalog.showRestParks ? catalog.restParks.length : 0;
  return featured + header + rest;
}

int? _sheetIndexForPark(ParkCatalogState catalog, String id) {
  final featuredIndex = catalog.parks.indexWhere((p) => p.id == id);
  if (featuredIndex >= 0) return featuredIndex;
  if (catalog.isSearching || catalog.restParks.isEmpty) return null;
  final restIndex = catalog.restParks.indexWhere((p) => p.id == id);
  if (restIndex < 0 || !catalog.showRestParks) return null;
  return catalog.parks.length + 1 + restIndex;
}

double _sheetRowExtent(_SheetEntry entry) {
  if (entry.isHeader) return 52;
  return 76;
}

_SheetEntry _sheetEntry(ParkCatalogState catalog, int index) {
  final featured = catalog.parks;
  if (index < featured.length) {
    return _SheetEntry.park(featured[index]);
  }
  var j = index - featured.length;
  if (!catalog.isSearching && catalog.restParks.isNotEmpty) {
    if (j == 0) return const _SheetEntry.header();
    j -= 1;
    if (catalog.showRestParks) {
      return _SheetEntry.park(catalog.restParks[j]);
    }
  }
  throw RangeError.index(index, featured, 'sheet index');
}

class _ParkTile extends StatelessWidget {
  const _ParkTile({
    required this.park,
    required this.selected,
    required this.onTap,
    required this.onOpenDetail,
    this.distance = '',
    this.vacancy,
  });

  final Park park;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;
  final String distance;
  final String? vacancy;

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
              if (park.hasEvCharging) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.bolt_rounded,
                  size: 18,
                  color: UberColors.accent,
                ),
              ],
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
                        park.priceAmountLabel,
                        ?vacancy,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: RType.muted(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (selected && park.freshnessLabel.isNotEmpty)
                      Text(
                        park.freshnessLabel,
                        style: RType.muted(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _PriceTrustIcon(park: park),
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

class _PriceTrustIcon extends StatelessWidget {
  const _PriceTrustIcon({required this.park});

  final Park park;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    if (park.isOperatorOfficial) {
      icon = Icons.verified_rounded;
      color = const Color(0xFF4C9EFF);
    } else if (park.isVerifiedPrice) {
      icon = Icons.fact_check_rounded;
      color = const Color(0xFF4C9EFF);
    } else if (park.isSeedDemoPrice || park.hasPrice) {
      icon = Icons.help_outline_rounded;
      color = UberColors.muted;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: park.priceBadgeLabel,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
