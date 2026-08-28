import 'package:flutter/material.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';

/// One-time explainer for the CWB/TST launch wedge (Phase A).
Future<void> showWedgeExplainerIfNeeded(BuildContext context) async {
  final seen = Bootstrap.store.getString(StorageKeys.wedgeExplained);
  if (seen == '1') return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: UberColors.sheet,
      title: Text('Recordo 泊車', style: RType.titleSm()),
      content: Text(
        '價錢由司機報 · 而家銅鑼灣同尖沙咀最齊。\n'
        '有「場內核實」係閘口核對過；「未核實」係示範價，歡迎你報價。',
        style: RType.body(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('知喇', style: RType.body()),
        ),
      ],
    ),
  );

  await Bootstrap.store.setString(StorageKeys.wedgeExplained, '1');
}
