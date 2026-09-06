import 'package:flutter/services.dart';
import 'package:recordo/features/parks/price_guard.dart';

/// On-device sign OCR → driver **suggestion** only (never official).
class SignOcrGuess {
  const SignOcrGuess({this.hourly, required this.raw});

  final double? hourly;
  final String raw;
}

abstract final class SignOcr {
  static const channel = MethodChannel('recordo/sign_ocr');

  static Future<String> recognizeFile(String path) async {
    final t = await channel.invokeMethod<String>('recognize', path);
    return (t ?? '').trim();
  }

  /// Pull a plausible **hourly** HKD from a parking sign. Skips 消費／免泊.
  static SignOcrGuess parse(String raw) {
    final text = raw.replaceAll('＄', r'$').replaceAll('港幣', r'$');
    final fromHour = <double>[];
    final fromDollar = <double>[];

    for (final line in text.split(RegExp(r'[\n\r]+'))) {
      if (_spendLine.hasMatch(line)) continue;
      for (final m in _hourlyNear.allMatches(line)) {
        final v = _clampHourly(_num(m));
        if (v != null) fromHour.add(v);
      }
      for (final m in _dollar.allMatches(line)) {
        final v = _clampHourly(_num(m));
        if (v != null) fromDollar.add(v);
      }
    }

    final hourly = fromHour.isNotEmpty
        ? fromHour.first
        : (fromDollar.where((e) => e >= 8 && e <= 80).firstOrNull ??
            fromDollar.firstOrNull);
    return SignOcrGuess(hourly: hourly, raw: raw.trim());
  }

  static final _spendLine = RegExp(r'消費|免費|發票|滿\$|滿 HK');

  static final _hourlyNear = RegExp(
    r'(?:每小時|時租|一小時|\/小時|/\s*hr)[^\d]{0,16}(?:HK)?\$?\s*(\d{1,3})'
    r'|(?:HK)?\$\s*(\d{1,3})\s*(?:\/\s*)?(?:每小時|一小時|小時)',
    caseSensitive: false,
  );
  static final _dollar = RegExp(r'(?:HK)?\$\s*(\d{1,3})', caseSensitive: false);

  static double? _num(RegExpMatch m) {
    for (var i = 1; i <= m.groupCount; i++) {
      final g = m.group(i);
      if (g == null) continue;
      return double.tryParse(g);
    }
    return null;
  }

  static double? _clampHourly(double? v) => PriceGuard.clampHourly(v);
}
