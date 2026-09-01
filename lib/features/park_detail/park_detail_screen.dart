import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/navigation/park_navigation.dart';
import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/features/parks/contribution_copy.dart';
import 'package:recordo/features/parks/hk_districts.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_tariff.dart';
import 'package:recordo/features/parks/park_ev.dart';
import 'package:recordo/features/parks/price_guard.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/session_cubit.dart';
import 'package:share_plus/share_plus.dart';

/// Park detail — map hero + price card + actions. No bottom dual CTA bar.
class ParkDetailScreen extends StatefulWidget {
  const ParkDetailScreen({super.key, required this.parkId});

  final String parkId;

  @override
  State<ParkDetailScreen> createState() => _ParkDetailScreenState();
}

class _ParkDetailScreenState extends State<ParkDetailScreen> {
  bool _editing = false;
  int _unitMinutes = 60;
  final _hourly = TextEditingController();
  final _daily = TextEditingController();
  final _night = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ParkCatalogCubit>().loadCommunityPaid(widget.parkId);
    });
  }

  @override
  void dispose() {
    _hourly.dispose();
    _daily.dispose();
    _night.dispose();
    _note.dispose();
    super.dispose();
  }

  void _prefill(Park p) {
    final t = p.tariff;
    if (t != null) {
      _unitMinutes = t.unitMinutes;
      final peak = t.bands.where((b) => b.kind == 'peak').firstOrNull;
      final off = t.bands.where((b) => b.kind == 'offpeak').firstOrNull;
      _hourly.text = peak?.amount.toStringAsFixed(0) ?? '';
      _night.text = off?.amount.toStringAsFixed(0) ?? '';
    } else {
      _unitMinutes = 60;
      _hourly.text = p.hourlyHkd?.toStringAsFixed(0) ?? '';
      _night.text = p.nightHkd?.toStringAsFixed(0) ?? '';
    }
    _daily.text = p.dailyHkd?.toStringAsFixed(0) ?? '';
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
      final updated = context.read<ParkCatalogCubit>().parkById(p.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ContributionCopy.priceConfirm(cloud: cloud, park: updated),
          ),
        ),
      );
    }
  }

  Future<void> _sharePark(BuildContext context, Park p) async {
    final lines = <String>[
      'Recordo · ${p.name}',
      if (p.district.isNotEmpty) p.district,
      if (p.address.isNotEmpty) p.address,
      if (p.hasPrice) p.priceSummary else '未有收費',
      'https://maps.google.com/?q=${p.lat},${p.lng}',
      '',
      '記低實付 · 銅鑼灣/尖沙咀 · 免費唔賣訂閱',
      'TestFlight 搜 Recordo 下載試用',
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
    HapticFeedback.lightImpact();
  }

  Future<void> _editIdentity(BuildContext context, Park p) async {
    if (!p.canEditIdentity) return;
    final nameCtrl = TextEditingController(text: p.name);
    var district = hkDistricts.contains(p.district) ? p.district : '';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: UberColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final kb = MediaQuery.viewInsetsOf(ctx).bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + kb),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('改名稱／地區', style: RType.titleSm()),
                  const SizedBox(height: 6),
                  Text('OSM 經常叫「地庫停車場」。幫大家改正確。', style: RType.muted()),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    style: RType.body(),
                    maxLength: 40,
                    decoration: InputDecoration(
                      hintText: '停車場名稱',
                      hintStyle: RType.muted(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 160,
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in hkDistricts)
                            ChoiceChip(
                              label: Text(d),
                              selected: district == d,
                              onSelected: (_) => setLocal(() => district = d),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('儲存'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || !context.mounted) return;
    try {
      final cloud = await context.read<ParkCatalogCubit>().reportIdentity(
            parkId: p.id,
            name: nameCtrl.text,
            district: district,
          );
      HapticFeedback.lightImpact();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cloud ? '已改 · 會同步去雲' : '已改 · 本機先記低')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('ArgumentError: ', ''))),
      );
    }
  }

  Future<void> _startTimer(BuildContext context, Park p) async {
    final session = context.read<SessionCubit>();
    if (session.state.active != null) {
      if (context.mounted) context.push('/session');
      return;
    }
    context.read<ParkCatalogCubit>().select(p.id);
    await session.start(
      parkId: p.id,
      parkName: p.name,
      hourlyLabel: p.hasPrice ? p.priceSummary : null,
    );
    HapticFeedback.mediumImpact();
    if (context.mounted) context.push('/session');
  }

  Future<void> _submit(BuildContext context, Park p) async {
    FocusManager.instance.primaryFocus?.unfocus();
    double? parse(TextEditingController c) {
      final t = c.text.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    final unitAmount = parse(_hourly);
    final daily = parse(_daily);
    final offpeak = parse(_night);
    final note = _note.text.trim();
    final hourly = unitAmount == null
        ? null
        : hourlyFromUnitAmount(unitAmount, _unitMinutes);
    final night = offpeak == null
        ? null
        : hourlyFromUnitAmount(offpeak, _unitMinutes);
    final tariff = unitAmount == null
        ? null
        : driverTariff(
            unitMinutes: _unitMinutes,
            peak: unitAmount,
            offpeak: offpeak,
          );

    final err = PriceGuard.validateReport(
      hourly: hourly,
      daily: daily,
      night: night,
      note: note,
      unitMinutes: _unitMinutes,
      unitAmount: unitAmount,
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
            unitMinutes: _unitMinutes,
            unitAmount: unitAmount,
            offpeakAmount: offpeak,
            tariff: tariff,
          );
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        setState(() => _editing = false);
        final updated = context.read<ParkCatalogCubit>().parkById(p.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ContributionCopy.priceReport(cloud: cloud, park: updated),
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
                      InkWell(
                        onTap: p.canEditIdentity
                            ? () => _editIdentity(context, p)
                            : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                style: RType.display().copyWith(fontSize: 26),
                              ),
                            ),
                            if (p.canEditIdentity)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 8),
                                child: Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: UberColors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          p.district,
                          if (dist.isNotEmpty) dist,
                          if (state.tdVacancyFor(p.id) != null)
                            state.tdVacancyFor(p.id)!.label,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: RType.muted(),
                      ),
                      if (p.address.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(p.address, style: RType.muted()),
                      ],
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
                            Text(p.priceBadgeLabel, style: RType.label()),
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
                              if (p.tariff != null)
                                _TariffCard(tariff: p.tariff!)
                              else
                                _PriceBreakdown(park: p),
                            ],
                            if (p.hasEvCharging) ...[
                              const SizedBox(height: 12),
                              Divider(height: 1, color: UberColors.hairline),
                              const SizedBox(height: 12),
                              _EvCard(ev: p.ev!),
                            ],
                            if (p.hasPriceNote && p.tariff == null) ...[
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

                      // Start timer — primary for Phase C cohort smoke path
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
                          onPressed: () => _startTimer(context, p),
                          icon: const Icon(Icons.timer_outlined),
                          label: const Text('開始計時'),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Navigate out
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: UberColors.white,
                            side: BorderSide(color: UberColors.hairline),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: () =>
                              ParkNavigation.showChooser(context, p),
                          icon: const Icon(Icons.directions_rounded, size: 18),
                          label: const Text('開始導航'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: UberColors.white,
                            side: BorderSide(color: UberColors.hairline),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: () => _sharePark(context, p),
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('分享呢個場'),
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
                                subtitle: p.isOperatorOfficial
                                    ? '官方牌 · 唔蓋'
                                    : '單位 / 每段收費',
                                onTap: p.isOperatorOfficial
                                    ? () {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              '官方牌價唔會用改價覆蓋。有出入就報實付。',
                                            ),
                                          ),
                                        );
                                      }
                                    : () {
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
                        const SizedBox(height: 8),
                        Text('計費單位', style: RType.label()),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final m in {
                              ...kBillingUnitChoices,
                              if (!kBillingUnitChoices.contains(_unitMinutes))
                                _unitMinutes,
                            })
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _unitMinutes = m),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _unitMinutes == m
                                        ? UberColors.accent
                                            .withValues(alpha: 0.18)
                                        : UberColors.sheet,
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(
                                      color: _unitMinutes == m
                                          ? UberColors.accent
                                          : UberColors.hairline,
                                    ),
                                  ),
                                  child: Text(
                                    billingUnitLabel(m),
                                    style: RType.label().copyWith(
                                      color: _unitMinutes == m
                                          ? UberColors.accent
                                          : UberColors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _field(
                          _hourly,
                          '繁忙 HK\$ / 每${_unitMinutes == 60 ? '小時' : '$_unitMinutes 分鐘'}',
                        ),
                        const SizedBox(height: 10),
                        _field(
                          _night,
                          '非繁忙 HK\$ / 每段（可空）',
                        ),
                        const SizedBox(height: 10),
                        _field(
                          _daily,
                          '日泊 HK\$（可空 · ${PriceGuard.dailyMin.toInt()}–${PriceGuard.dailyMax.toInt()}）',
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

/// Recent real payments — community (cloud) + local session history.
class _PaidHistoryCard extends StatelessWidget {
  const _PaidHistoryCard({required this.parkId});
  final String parkId;

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '$h 小時 $m 分';
    return '$m 分鐘';
  }

  static String _fmtWhen(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前';
    if (d.inHours < 48) return '${d.inHours} 小時前';
    return '${d.inDays} 日前';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ParkCatalogCubit, ParkCatalogState>(
      buildWhen: (prev, next) =>
          prev.communityPaidByPark[parkId] != next.communityPaidByPark[parkId] ||
          prev.communityPaidLoading.contains(parkId) !=
              next.communityPaidLoading.contains(parkId),
      builder: (context, cat) {
        return BlocBuilder<SessionCubit, SessionState>(
          builder: (context, session) {
            final local =
                context.read<SessionCubit>().paidSessionsForPark(parkId);
            final community = cat.communityPaidFor(parkId);
            final loading = cat.communityPaidLoadingFor(parkId);
            final hasCommunity = community.isNotEmpty;
            final hasLocal = local.isNotEmpty;

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
                  if (RecordoSupabase.isReady && hasCommunity) ...[
                    const SizedBox(height: 4),
                    Text('其他司機分享', style: RType.muted()),
                  ],
                  const SizedBox(height: 6),
                  if (loading && !hasCommunity && !hasLocal)
                    Text('載入中…', style: RType.muted())
                  else if (!hasCommunity && !hasLocal)
                    Text(
                      '未有實付 · 泊完填收費就會出現',
                      style: RType.muted(),
                    )
                  else ...[
                    if (hasCommunity)
                      for (var i = 0; i < community.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'HK\$${community[i].amountHkd.toStringAsFixed(0)} · ${_fmtDur(community[i].duration)}',
                                style: RType.body(),
                              ),
                            ),
                            Text(
                              _fmtWhen(community[i].createdAt),
                              style: RType.muted(),
                            ),
                          ],
                        ),
                      ],
                    if (hasLocal) ...[
                      if (hasCommunity) ...[
                        const SizedBox(height: 12),
                        Text('本機', style: RType.muted()),
                        const SizedBox(height: 6),
                      ],
                      for (var i = 0; i < local.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'HK\$${local[i].amountHkd!.toStringAsFixed(0)} · ${_fmtDur(local[i].elapsed)}',
                                style: RType.body(),
                              ),
                            ),
                            Text(
                              _fmtWhen(local[i].endedAt!),
                              style: RType.muted(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

SliverToBoxAdapter sliverToBox({required Widget child}) =>
    SliverToBoxAdapter(child: child);

class _TariffCard extends StatelessWidget {
  const _TariffCard({required this.tariff});
  final ParkTariff tariff;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('按${tariff.unitLabel}計', style: RType.label()),
        const SizedBox(height: 10),
        for (final days in tariff.dayOrder) ...[
          Text(tariff.bands.firstWhere((b) => b.days == days).daysLabel,
              style: RType.body()),
          const SizedBox(height: 6),
          for (final b in tariff.bands.where((e) => e.days == days)) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${b.kindLabel}（${b.windowLabel}）',
                    style: RType.muted(),
                  ),
                ),
                Text(
                  b.isPackage
                      ? moneyLabel(b.amount, tariff.currency)
                      : '${moneyLabel(b.amount, tariff.currency)} / ${tariff.unitLabel}',
                  style: RType.body(),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 6),
        ],
        if (tariff.validations.isNotEmpty) ...[
          const SizedBox(height: 4),
          Divider(height: 1, color: UberColors.hairline),
          const SizedBox(height: 10),
          Text('商場優惠', style: RType.label()),
          const SizedBox(height: 6),
          for (final v in tariff.validations) ...[
            Text(v.line(currency: tariff.currency), style: RType.muted()),
            const SizedBox(height: 4),
          ],
        ],
      ],
    );
  }
}

class _EvCard extends StatelessWidget {
  const _EvCard({required this.ev});
  final ParkEv ev;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, size: 16, color: UberColors.accent),
            const SizedBox(width: 4),
            Text('充電', style: RType.label()),
          ],
        ),
        const SizedBox(height: 8),
        for (final c in ev.connectors) ...[
          Text(c.line, style: RType.muted()),
          const SizedBox(height: 4),
        ],
        for (final b in ev.billing) ...[
          Text(b.line, style: RType.body()),
          const SizedBox(height: 4),
        ],
        if (ev.billing.any((e) => e.model == 'bundledWithParking'))
          Text('連充電價唔計入時租 chip', style: RType.muted()),
      ],
    );
  }
}

class _PriceBreakdown extends StatelessWidget {
  const _PriceBreakdown({required this.park});
  final Park park;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (park.hourlyHkd != null)
        ('時租', moneyLabel(park.hourlyHkd!, park.currency)),
      if (park.dailyHkd != null)
        ('日泊', moneyLabel(park.dailyHkd!, park.currency)),
      if (park.nightHkd != null)
        ('夜泊', moneyLabel(park.nightHkd!, park.currency)),
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
                maxNativeZoom: UberColors.mapMaxNativeZoom,
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
