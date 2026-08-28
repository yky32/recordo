import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/end_session_flow.dart';
import 'package:recordo/features/session/parking_session.dart';
import 'package:recordo/features/session/session_cubit.dart';

/// Shared 「結束 · 填收費」sheet. Returns true if saved.
Future<bool> showEndSessionSheet(BuildContext context) async {
  final sessionCubit = context.read<SessionCubit>();
  final session = sessionCubit.state.active;
  if (session == null) return false;

  final catalogCubit = context.read<ParkCatalogCubit>();
  final park = session.parkId != null
      ? catalogCubit.parkById(session.parkId!)
      : catalogCubit.state.selected;

  final result = await showModalBottomSheet<_EndResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: UberColors.sheet,
    builder: (ctx) => _EndSessionSheetBody(
      session: session,
      park: park,
    ),
  );

  if (result == null || !context.mounted) return false;

  final outcome = await EndSessionFlow.complete(
    sessionCubit: sessionCubit,
    catalogCubit: catalogCubit,
    active: session,
    amountHkd: result.amount,
    sharePaid: result.sharePaid,
    park: park,
  );

  if (!context.mounted || outcome == null) return false;

  HapticFeedback.lightImpact();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(outcome.snackMessage)),
  );
  return outcome.saved;
}

class _EndResult {
  const _EndResult({required this.amount, required this.sharePaid});
  final double amount;
  final bool sharePaid;
}

/// Owns [TextEditingController] for the sheet lifetime only.
class _EndSessionSheetBody extends StatefulWidget {
  const _EndSessionSheetBody({
    required this.session,
    this.park,
  });

  final ParkingSession session;
  final Park? park;

  @override
  State<_EndSessionSheetBody> createState() => _EndSessionSheetBodyState();
}

class _EndSessionSheetBodyState extends State<_EndSessionSheetBody> {
  late final TextEditingController _amountCtrl;
  late bool _sharePaid;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    _sharePaid = widget.park != null;
    final hourly = widget.park?.hourlyHkd;
    if (hourly != null && hourly > 0) {
      final hours = widget.session.elapsed.inSeconds / 3600.0;
      final est = hourly * (hours < 1 / 60 ? 1 / 60 : hours);
      _amountCtrl.text = est.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final park = widget.park;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
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
            controller: _amountCtrl,
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
              border: UberColors.fieldOutline(),
              enabledBorder: UberColors.fieldOutline(),
              focusedBorder: UberColors.fieldOutline(focused: true),
            ),
          ),
          const SizedBox(height: 12),
          if (park != null)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('分享實付俾其他司機', style: RType.body()),
              subtitle: Text(
                '只分享金額同泊車時間 · 唔會改場價',
                style: RType.muted(),
              ),
              value: _sharePaid,
              activeThumbColor: UberColors.accent,
              onChanged: (v) => setState(() => _sharePaid = v),
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
              final v = double.tryParse(_amountCtrl.text.trim());
              if (v == null || v < 0) return;
              Navigator.pop(
                context,
                _EndResult(amount: v, sharePaid: _sharePaid),
              );
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
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
