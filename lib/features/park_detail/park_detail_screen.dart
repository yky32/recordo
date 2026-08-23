import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';

class ParkDetailScreen extends StatefulWidget {
  const ParkDetailScreen({super.key, required this.parkId});

  final String parkId;

  @override
  State<ParkDetailScreen> createState() => _ParkDetailScreenState();
}

class _ParkDetailScreenState extends State<ParkDetailScreen> {
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ParkCatalogCubit, ParkCatalogState>(
      builder: (context, state) {
        final p = state.parks.where((e) => e.id == widget.parkId).firstOrNull;
        if (p == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Park')),
            body: const Center(child: Text('Not found')),
          );
        }

        return Scaffold(
          backgroundColor: UberColors.black,
          appBar: AppBar(
            title: Text(p.name, style: RType.titleSm()),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text(p.district, style: RType.muted()),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: UberColors.elevated,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Community price', style: RType.label()),
                    const SizedBox(height: 8),
                    Text(p.priceSummary, style: RType.display()),
                    const SizedBox(height: 6),
                    Text(p.freshnessLabel, style: RType.muted()),
                    if (p.heightM != null) ...[
                      const SizedBox(height: 8),
                      Text('Max height ~${p.heightM}m', style: RType.body()),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Prices are UGC — not Google, not operators. '
                'Confirm or fix so the next driver trusts Recordo.',
                style: RType.muted(),
              ),
              const SizedBox(height: 20),
              if (p.hasPrice)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: UberColors.accent,
                    foregroundColor: UberColors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
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
                        const SnackBar(content: Text('Thanks — price confirmed')),
                      );
                    }
                  },
                  child: const Text('Still correct'),
                ),
              const SizedBox(height: 12),
              Text('Report / fix price', style: RType.titleSm()),
              const SizedBox(height: 10),
              _field(_hourly, 'Hourly HK\$'),
              const SizedBox(height: 8),
              _field(_daily, 'Daily HK\$ (optional)'),
              const SizedBox(height: 8),
              _field(_night, 'Night HK\$ (optional)'),
              const SizedBox(height: 14),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: UberColors.white,
                  side: const BorderSide(color: UberColors.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () async {
                  double? parse(TextEditingController c) =>
                      double.tryParse(c.text.trim());
                  await context.read<ParkCatalogCubit>().reportPrice(
                        parkId: p.id,
                        hourly: parse(_hourly) ?? p.hourlyHkd,
                        daily: parse(_daily) ?? p.dailyHkd,
                        night: parse(_night) ?? p.nightHkd,
                      );
                  HapticFeedback.mediumImpact();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Price updated for everyone later')),
                    );
                    Navigator.pop(context);
                  }
                },
                child: const Text('Submit UGC price'),
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
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
