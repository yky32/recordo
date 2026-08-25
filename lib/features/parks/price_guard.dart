/// Server-aligned clamps for UGC prices (HK parking sanity).
abstract final class PriceGuard {
  static const hourlyMin = 1.0;
  static const hourlyMax = 500.0;
  static const dailyMin = 10.0;
  static const dailyMax = 3000.0;
  static const nightMin = 10.0;
  static const nightMax = 2000.0;
  static const noteMaxLen = 200;

  static double? clampHourly(double? v) {
    if (v == null) return null;
    if (v.isNaN || v.isInfinite) return null;
    if (v < hourlyMin || v > hourlyMax) return null;
    return v.roundToDouble();
  }

  static double? clampDaily(double? v) {
    if (v == null) return null;
    if (v.isNaN || v.isInfinite) return null;
    if (v < dailyMin || v > dailyMax) return null;
    return v.roundToDouble();
  }

  static double? clampNight(double? v) {
    if (v == null) return null;
    if (v.isNaN || v.isInfinite) return null;
    if (v < nightMin || v > nightMax) return null;
    return v.roundToDouble();
  }

  static String clampNote(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return '';
    if (t.length <= noteMaxLen) return t;
    return t.substring(0, noteMaxLen);
  }

  /// null = OK; else user-facing error in 粵/書面.
  static String? validateReport({
    double? hourly,
    double? daily,
    double? night,
    String? note,
    bool confirmOnly = false,
  }) {
    if (!confirmOnly &&
        hourly == null &&
        daily == null &&
        night == null &&
        (note == null || note.trim().isEmpty)) {
      return '請至少填一個價錢或備註';
    }
    if (hourly != null && (hourly < hourlyMin || hourly > hourlyMax)) {
      return '時租請介乎 HK\$${hourlyMin.toInt()}–${hourlyMax.toInt()}';
    }
    if (daily != null && (daily < dailyMin || daily > dailyMax)) {
      return '日泊請介乎 HK\$${dailyMin.toInt()}–${dailyMax.toInt()}';
    }
    if (night != null && (night < nightMin || night > nightMax)) {
      return '夜泊請介乎 HK\$${nightMin.toInt()}–${nightMax.toInt()}';
    }
    if (note != null && note.trim().length > noteMaxLen) {
      return '備註最多 $noteMaxLen 字';
    }
    return null;
  }
}
