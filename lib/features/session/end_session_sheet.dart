import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/session_cubit.dart';

/// Shared 「結束 · 填收費」sheet. Returns true if saved.
Future<bool> showEndSessionSheet(BuildContext context) async {
  final session = context.read<SessionCubit>().state.active;
  if (session == null) return false;

  final amountCtrl = TextEditingController();
  final catalog = context.read<ParkCatalogCubit>();
  final park = session.parkId != null
      ? catalog.parkById(session.parkId!)
      : catalog.state.selected;
  var updatePrice = park != null;

  // Prefill estimate if we have hourly
  final hourly = park?.hourlyHkd;
  if (hourly != null && hourly > 0) {
    final hours = session.elapsed.inSeconds / 3600.0;
    final est = hourly * (hours < 1 / 60 ? 1 / 60 : hours);
    amountCtrl.text = est.toStringAsFixed(0);
  }

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
                Text('今次泊咗幾多錢？', style: RType.muted()),
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
                if (park != null)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('順便更新場價', style: RType.body()),
                    value: updatePrice,
                    activeThumbColor: UberColors.accent,
                    onChanged: (v) => setModal(() => updatePrice = v),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: UberColors.ctaFill,
                    foregroundColor: UberColors.ctaOnFill,
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

  if (ok != true || !context.mounted) {
    amountCtrl.dispose();
    return false;
  }

  final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
  amountCtrl.dispose();

  await context.read<SessionCubit>().end(
        amountHkd: amount,
        parkId: park?.id ?? session.parkId,
        parkName: park?.name ?? session.parkName,
      );

  if (updatePrice && park != null && amount > 0 && context.mounted) {
    final hours = session.elapsed.inMinutes / 60.0;
    final hourlyGuess = hours >= 0.25 ? (amount / hours) : amount;
    await catalog.reportPrice(
      parkId: park.id,
      hourly: double.parse(hourlyGuess.toStringAsFixed(0)),
    );
  }

  if (context.mounted) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已記低')),
    );
  }
  return true;
}

/// Rough running total from hourly rate.
double? estimateParkingFee(Duration elapsed, double? hourlyHkd) {
  if (hourlyHkd == null || hourlyHkd <= 0) return null;
  final hours = elapsed.inSeconds / 3600.0;
  if (hours <= 0) return 0;
  return hourlyHkd * hours;
}

String formatSessionDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}
