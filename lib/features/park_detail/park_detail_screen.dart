import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/navigation/park_navigation.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';

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

  @override
  void dispose() {
    _hourly.dispose();
    _daily.dispose();
    _night.dispose();
    super.dispose();
  }

  void _prefill(Park p) {
    _hourly.text = p.hourlyHkd?.toStringAsFixed(0) ?? '';
    _daily.text = p.dailyHkd?.toStringAsFixed(0) ?? '';
    _night.text = p.nightHkd?.toStringAsFixed(0) ?? '';
  }

  Future<void> _confirm(BuildContext context, Park p) async {
    await context.read<ParkCatalogCubit>().reportPrice(
          parkId: p.id,
          hourly: p.hourlyHkd,
          daily: p.dailyHkd,
          night: p.nightHkd,
          confirmOnly: true,
        );
    HapticFeedback.lightImpact();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('多謝 · 已確認價錢仍然啱')),
      );
    }
  }

  Future<void> _submit(BuildContext context, Park p) async {
    FocusManager.instance.primaryFocus?.unfocus();
    double? parse(TextEditingController c) => double.tryParse(c.text.trim());
    await context.read<ParkCatalogCubit>().reportPrice(
          parkId: p.id,
          hourly: parse(_hourly) ?? p.hourlyHkd,
          daily: parse(_daily) ?? p.dailyHkd,
          night: parse(_night) ?? p.nightHkd,
        );
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已更新場價')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return BlocBuilder<ParkCatalogCubit, ParkCatalogState>(
      builder: (context, state) {
        final p = state.parks.where((e) => e.id == widget.parkId).firstOrNull;
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
                  icon: const Icon(Icons.close_rounded),
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 168,
                          width: double.infinity,
                          child: _MiniMap(park: p),
                        ),
                      ),
                      const SizedBox(height: 20),
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
                          border: Border.all(
                            color: UberColors.hairline.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('司機報價', style: RType.label()),
                            const SizedBox(height: 8),
                            Text(
                              p.hasPrice ? p.priceSummary : '未有收費',
                              style: RType.display().copyWith(fontSize: 28),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              p.hasPrice
                                  ? p.freshnessLabel
                                  : '未有人報過 · 你可以做第一個',
                              style: RType.muted(),
                            ),
                            if (p.hasPrice) ...[
                              const SizedBox(height: 14),
                              const Divider(height: 1, color: UberColors.hairline),
                              const SizedBox(height: 12),
                              _PriceBreakdown(park: p),
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

                      const SizedBox(height: 14),
                      Text(
                        '價錢由用家更新，唔係 Google 或場方官方。',
                        style: RType.muted(),
                      ),

                      const SizedBox(height: 20),

                      // Navigate out — primary after user likes the park
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: UberColors.white,
                            foregroundColor: UberColors.black,
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
                                  icon: Icons.check_circle_outline_rounded,
                                  title: '價錢仍然啱',
                                  subtitle: '確認收費',
                                  accent: true,
                                  onTap: () => _confirm(context, p),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: _ActionHalf(
                                icon: Icons.edit_outlined,
                                title: '改收費',
                                subtitle: '時 / 日 / 夜',
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
                        const SizedBox(height: 18),
                        Text('更新收費', style: RType.titleSm()),
                        const SizedBox(height: 12),
                        _field(_hourly, '時租 HK\$'),
                        const SizedBox(height: 10),
                        _field(_daily, '日泊 HK\$（可空）'),
                        const SizedBox(height: 10),
                        _field(_night, '夜泊 HK\$（可空）'),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: UberColors.white,
                              foregroundColor: UberColors.black,
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

  Widget _field(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: RType.body(),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: RType.muted(),
        filled: true,
        fillColor: UberColors.elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
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
    return Material(
      color: accent ? const Color(0xFF1A2E1A) : UberColors.elevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: accent ? UberColors.accent : UberColors.white,
                size: 22,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: RType.body(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: RType.muted(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
            urlTemplate:
                'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            userAgentPackageName: 'com.recordo',
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
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.local_parking_rounded,
                    color: UberColors.black,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
