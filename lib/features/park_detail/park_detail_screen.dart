import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/navigation/park_navigation.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/price_guard.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/session_cubit.dart';

/// Park detail — map hero + price card + actions. No bottom dual CTA bar.
class ParkDetailScreen extends StatefulWidget {
  const ParkDetailScreen({super.key, required this.parkId});

  final String parkId;

  @override
  State<ParkDetailScreen> createState() => _ParkDetailScreenState();
}

class _ParkDetailScreenState extends State<ParkDetailScreen> {
  bool _editing = false;
  final _hourly = TextEditingController();
  final _daily = TextEditingController();
  final _night = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _hourly.dispose();
    _daily.dispose();
    _night.dispose();
    _note.dispose();
    super.dispose();
  }

  void _prefill(Park p) {
    _hourly.text = p.hourlyHkd?.toStringAsFixed(0) ?? '';
    _daily.text = p.dailyHkd?.toStringAsFixed(0) ?? '';
    _night.text = p.nightHkd?.toStringAsFixed(0) ?? '';
    _note.text = p.priceNote;
  }

  Future<void> _confirm(BuildContext context, Park p) async {
    final cloud = await context.read<ParkCatalogCubit>().reportPrice(
          parkId: p.id,
          hourly: p.hourlyHkd,
          daily: p.dailyHkd,
          night: p.nightHkd,
          confirmOnly: true,
        );
    HapticFeedback.lightImpact();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cloud
                ? '多謝 · 已確認，並分享到雲端'
                : '多謝 · 已確認（本機 · 稍後有網會再同步）',
          ),
        ),
      );
    }
  }

  Future<void> _submit(BuildContext context, Park p) async {
    FocusManager.instance.primaryFocus?.unfocus();
    double? parse(TextEditingController c) {
      final t = c.text.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    final hourly = parse(_hourly);
    final daily = parse(_daily);
    final night = parse(_night);
    final note = _note.text.trim();

    final err = PriceGuard.validateReport(
      hourly: hourly,
      daily: daily,
      night: night,
      note: note,
    );
    if (err != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
      return;
    }

    try {
      final cloud = await context.read<ParkCatalogCubit>().reportPrice(
            parkId: p.id,
            hourly: hourly,
            daily: daily,
            night: night,
            priceNote: note,
          );
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        setState(() => _editing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cloud
                  ? '已更新場價 · 已分享給其他 Recordo 用戶'
                  : '已更新場價（本機 · 連雲端失敗或未設定）',
            ),
          ),
        );
      }
    } on ArgumentError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message?.toString() ?? '價錢無效')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return BlocBuilder<ParkCatalogCubit, ParkCatalogState>(
      builder: (context, state) {
        final p = state.parks.where((e) => e.id == widget.parkId).firstOrNull ??
            context.read<ParkCatalogCubit>().parkById(widget.parkId);
        if (p == null) {
          return Scaffold(
            backgroundColor: UberColors.black,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text('場詳情', style: RType.titleSm()),
              centerTitle: true,
            ),
            body: const Center(child: Text('找不到呢個場')),
          );
        }

        final dm = context.read<ParkCatalogCubit>().distanceMeters(p);
        final dist = ParkCatalogCubit.formatDistance(dm);

        return Scaffold(
          backgroundColor: UberColors.black,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: UberColors.black,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                centerTitle: true,
                title: Text('場詳情', style: RType.titleSm()),
              ),
              sliverToBox(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 28 + bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Map
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: UberColors.hairline),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: SizedBox(
                            height: 168,
                            width: double.infinity,
                            child: _MiniMap(park: p),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        p.name,
                        style: RType.display().copyWith(fontSize: 26),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          p.district,
                          if (dist.isNotEmpty) dist,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: RType.muted(),
                      ),
                      const SizedBox(height: 18),

                      // —— Price card (main info block) ——
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        decoration: BoxDecoration(
                          color: UberColors.elevated,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: UberColors.hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('司機報價', style: RType.label()),
                            SizedBox(height: 8),
                            Text(
                              p.hasPrice ? p.priceSummary : '未有收費',
                              style: RType.display().copyWith(fontSize: 28),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p.trustLabel,
                                    style: RType.muted(),
                                  ),
                                ),
                                if (p.trustTooltip != null) ...[
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: p.trustTooltip!,
                                    triggerMode: TooltipTriggerMode.tap,
                                    waitDuration: Duration.zero,
                                    showDuration: const Duration(seconds: 3),
                                    child: Icon(
                                      Icons.info_outline_rounded,
                                      size: 15,
                                      color: UberColors.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (p.hasPrice) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: UberColors.muted,
                                  ),
                                  const SizedBox(width: 4),
                                  if (p.freshnessAgoLabel.isNotEmpty)
                                    Flexible(
                                      child: Text(
                                        p.freshnessAgoLabel,
                                        style: RType.muted(),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  else if (p.ugcConfirms <= 0)
                                    Text('未有人更新', style: RType.muted()),
                                  if (p.ugcConfirms > 0) ...[
                                    if (p.freshnessAgoLabel.isNotEmpty)
                                      Text(' · ', style: RType.muted()),
                                    Icon(
                                      Icons.person_rounded,
                                      size: 14,
                                      color: UberColors.muted,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      p.freshnessAgoLabel.isEmpty
                                          ? '${p.ugcConfirms} 人報告'
                                          : '${p.ugcConfirms} 人',
                                      style: RType.muted(),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 14),
                              Divider(height: 1, color: UberColors.hairline),
                              SizedBox(height: 12),
                              _PriceBreakdown(park: p),
                            ],
                            if (p.hasPriceNote) ...[
                              const SizedBox(height: 12),
                              Text('收費備註', style: RType.label()),
                              const SizedBox(height: 4),
                              Text(p.priceNote, style: RType.body()),
                            ],
                            if (p.heightM != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                '限高約 ${p.heightM}m',
                                style: RType.muted(),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),
                      _PaidHistoryCard(parkId: p.id),

                      const SizedBox(height: 20),

                      // Navigate out — primary after user likes the park
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: UberColors.ctaFill,
                            foregroundColor: UberColors.ctaOnFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: () =>
                              ParkNavigation.showChooser(context, p),
                          icon: const Icon(Icons.directions_rounded),
                          label: const Text('開始導航'),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // —— Actions: 50/50 one row ——
                      if (!_editing)
                        Row(
                          children: [
                            if (p.hasPrice) ...[
                              Expanded(
                                child: _ActionHalf(
                                  icon: Icons.check_rounded,
                                  title: '確認',
                                  subtitle: '價錢仍然啱',
                                  accent: true,
                                  onTap: () => _confirm(context, p),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: _ActionHalf(
                                icon: Icons.edit_outlined,
                                title: '改價',
                                subtitle: '時 / 日 / 夜 / 備註',
                                onTap: () {
                                  setState(() {
                                    _editing = true;
                                    _prefill(p);
                                  });
                                },
                              ),
                            ),
                          ],
                        )
                      else
                        _ActionHalf(
                          icon: Icons.keyboard_arrow_up_rounded,
                          title: '收起改價',
                          subtitle: '返回',
                          onTap: () => setState(() => _editing = false),
                        ),

                      if (_editing) ...[
                        SizedBox(height: 18),
                        Text('更新收費', style: RType.titleSm()),
                        const SizedBox(height: 12),
                        _field(
                          _hourly,
                          '時租 HK\$（${PriceGuard.hourlyMin.toInt()}–${PriceGuard.hourlyMax.toInt()}）',
                        ),
                        const SizedBox(height: 10),
                        _field(
                          _daily,
                          '日泊 HK\$（可空 · ${PriceGuard.dailyMin.toInt()}–${PriceGuard.dailyMax.toInt()}）',
                        ),
                        const SizedBox(height: 10),
                        _field(
                          _night,
                          '夜泊 HK\$（可空 · ${PriceGuard.nightMin.toInt()}–${PriceGuard.nightMax.toInt()}）',
                        ),
                        const SizedBox(height: 10),
                        _field(
                          _note,
                          '備註 · 例如：首小時 \$30 · 之後每半鐘 \$15',
                          maxLines: 3,
                          keyboardType: TextInputType.multiline,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: UberColors.ctaFill,
                              foregroundColor: UberColors.ctaOnFill,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            onPressed: () => _submit(context, p),
                            child: const Text('提交更新'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboardType ??
          const TextInputType.numberWithOptions(decimal: true),
      style: RType.body(),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: RType.muted(),
        alignLabelWithHint: maxLines > 1,
        filled: true,
        fillColor: UberColors.elevated,
        border: UberColors.fieldOutline(),
        enabledBorder: UberColors.fieldOutline(),
        focusedBorder: UberColors.fieldOutline(focused: true),
      ),
    );
  }
}

/// Recent real payments from local session history (this device).
class _PaidHistoryCard extends StatelessWidget {
  const _PaidHistoryCard({required this.parkId});
  final String parkId;

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '$h 小時 $m 分';
    return '$m 分鐘';
  }

  String _fmtWhen(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前';
    if (d.inHours < 48) return '${d.inHours} 小時前';
    return '${d.inDays} 日前';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      builder: (context, session) {
        final paid =
            context.read<SessionCubit>().paidSessionsForPark(parkId);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: UberColors.elevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: UberColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('最近實付', style: RType.label()),
              const SizedBox(height: 6),
              if (paid.isEmpty)
                Text(
                  '完結計時並填收費後，會出現喺呢度 · 幫你知真實落閘幾錢',
                  style: RType.muted(),
                )
              else ...[
                for (var i = 0; i < paid.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'HK\$${paid[i].amountHkd!.toStringAsFixed(0)} · ${_fmtDur(paid[i].elapsed)}',
                          style: RType.body(),
                        ),
                      ),
                      Text(
                        _fmtWhen(paid[i].endedAt!),
                        style: RType.muted(),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

SliverToBoxAdapter sliverToBox({required Widget child}) =>
    SliverToBoxAdapter(child: child);

class _PriceBreakdown extends StatelessWidget {
  const _PriceBreakdown({required this.park});
  final Park park;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (park.hourlyHkd != null)
        ('時租', 'HK\$${park.hourlyHkd!.toStringAsFixed(0)}'),
      if (park.dailyHkd != null)
        ('日泊', 'HK\$${park.dailyHkd!.toStringAsFixed(0)}'),
      if (park.nightHkd != null)
        ('夜泊', 'HK\$${park.nightHkd!.toStringAsFixed(0)}'),
    ];
    if (rows.isEmpty) {
      return Text(park.priceSummary, style: RType.body());
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Text(rows[i].$1, style: RType.muted()),
              const Spacer(),
              Text(rows[i].$2, style: RType.body()),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActionHalf extends StatelessWidget {
  const _ActionHalf({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? UberColors.accent : UberColors.white;
    const shape = StadiumBorder();
    return Tooltip(
      message: subtitle,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        height: 48,
        child: Material(
          color: accent
              ? UberColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: shape.copyWith(
            side: BorderSide(
              color: accent
                  ? UberColors.accent.withValues(alpha: 0.4)
                  : UberColors.hairline,
            ),
          ),
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: fg, size: 18),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      title,
                      style: RType.body().copyWith(
                        color: fg,
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.park});
  final Park park;

  @override
  Widget build(BuildContext context) {
    final pt = LatLng(park.lat, park.lng);
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return AbsorbPointer(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: pt,
              initialZoom: 15.2,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
              backgroundColor: UberColors.mapBlock,
            ),
            children: [
              TileLayer(
                key: ValueKey(UberColors.mapTileUrl),
                urlTemplate: UberColors.mapTileUrl,
                fallbackUrl: UberColors.mapTileFallback,
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.recordo',
                retinaMode: false,
                maxNativeZoom: 19,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: pt,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: UberColors.accent,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: UberColors.onAccent, width: 2),
                      ),
                      child: const Icon(
                        Icons.local_parking_rounded,
                        color: UberColors.onAccent,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

extension<E> on Iterable<E> {
  E? get firstOrNull {
    final i = iterator;
    if (!i.moveNext()) return null;
    return i.current;
  }
}
