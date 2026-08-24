import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';

/// Park detail — Uber trip-detail density (map strip, hero, rows, bottom CTA).
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
        const SnackBar(content: Text('已確認')),
      );
    }
  }

  Future<void> _submit(BuildContext context, Park p) async {
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
        const SnackBar(content: Text('已更新')),
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
          body: Column(
            children: [
              Expanded(
                child: CustomScrollView(
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
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Map strip (Uber-style)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                height: 160,
                                width: double.infinity,
                                child: _MiniMap(park: p),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Hero title
                            Text(
                              p.name,
                              style: RType.display().copyWith(fontSize: 26),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              [
                                p.district,
                                if (dist.isNotEmpty) dist,
                                p.freshnessLabel,
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: RType.muted(),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              p.hasPrice ? p.priceSummary : '未有收費',
                              style: RType.title().copyWith(fontSize: 22),
                            ),
                            if (p.heightM != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '限高約 ${p.heightM}m',
                                style: RType.muted(),
                              ),
                            ],
                            const SizedBox(height: 16),
                            // Chip actions
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (p.hasPrice)
                                  _ChipButton(
                                    icon: Icons.check_rounded,
                                    label: '價錢仍然啱',
                                    filled: true,
                                    onTap: () => _confirm(context, p),
                                  ),
                                _ChipButton(
                                  icon: Icons.edit_outlined,
                                  label: _editing ? '收起' : '改收費',
                                  filled: false,
                                  onTap: () {
                                    setState(() {
                                      _editing = !_editing;
                                      if (_editing) _prefill(p);
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            // Divider section — Uber list rows
                            Text('資料', style: RType.titleSm()),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildListDelegate([
                        _InfoRow(
                          icon: Icons.payments_outlined,
                          title: '司機報價',
                          trailing: p.hasPrice ? p.priceSummary : '未有',
                        ),
                        _InfoRow(
                          icon: Icons.schedule_outlined,
                          title: '更新時間',
                          trailing: p.freshnessLabel,
                        ),
                        if (p.heightM != null)
                          _InfoRow(
                            icon: Icons.height_rounded,
                            title: '限高',
                            trailing: '~${p.heightM}m',
                          ),
                        _InfoRow(
                          icon: Icons.place_outlined,
                          title: '地區',
                          trailing: p.district,
                        ),
                        _InfoRow(
                          icon: Icons.info_outline_rounded,
                          title: '價錢來源',
                          trailing: '用家更新',
                          subtitle: '唔係 Google 或場方官方價',
                        ),
                        if (_editing) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Text('改收費', style: RType.titleSm()),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: _field(_hourly, '時租 HK\$'),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: _field(_daily, '日泊 HK\$（可空）'),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: _field(_night, '夜泊 HK\$（可空）'),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: UberColors.white,
                                foregroundColor: UberColors.black,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              onPressed: () => _submit(context, p),
                              child: const Text('提交更新'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ],
                ),
              ),
              // Bottom bar — Uber style
              Material(
                color: UberColors.elevated,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom * 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: UberColors.white,
                              side: const BorderSide(color: UberColors.hairline),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            onPressed: () {
                              // Select this park on map & pop
                              context
                                  .read<ParkCatalogCubit>()
                                  .select(p.id);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.near_me_outlined, size: 20),
                            label: const Text('用地圖睇'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: UberColors.white,
                              foregroundColor: UberColors.black,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            onPressed: () {
                              context
                                  .read<ParkCatalogCubit>()
                                  .select(p.id);
                              Navigator.pop(context);
                              // Parent sheet shows slide CTA after select
                            },
                            child: const Text('揀呢個場'),
                          ),
                        ),
                      ],
                    ),
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

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? UberColors.elevated2 : UberColors.elevated,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: UberColors.white),
              const SizedBox(width: 8),
              Text(label, style: RType.body()),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.trailing,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: UberColors.hairline, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: UberColors.muted, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: RType.body()),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: RType.muted()),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              trailing,
              style: RType.muted(),
              textAlign: TextAlign.end,
            ),
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
