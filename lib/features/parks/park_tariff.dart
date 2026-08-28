/// HK mall / car-park tariff. Times Square is the reference shape:
/// billed per 30 min, weekday vs weekend+PH, peak vs overnight, mall validation.
class ParkTariff {
  const ParkTariff({
    required this.unitMinutes,
    required this.bands,
    this.validations = const [],
    this.sourceName,
  });

  /// 30 = 半小時 (Times Square / most malls). 60 = 每小時.
  final int unitMinutes;
  final List<TariffBand> bands;
  final List<TariffValidation> validations;
  final String? sourceName;

  String get unitLabel => unitMinutes == 30 ? '半小時' : '小時';

  double get _perHourFactor => 60 / unitMinutes;

  /// Chip number: weekday peak converted to hourly.
  double? get weekdayPeakHourly {
    final b = _band(days: 'mon-fri', kind: 'peak') ??
        (bands.isEmpty ? null : bands.first);
    if (b == null) return null;
    return b.amount * _perHourFactor;
  }

  double? get weekdayOffpeakHourly {
    final b = _band(days: 'mon-fri', kind: 'offpeak');
    if (b == null) return null;
    return b.amount * _perHourFactor;
  }

  TariffBand? _band({required String days, required String kind}) {
    for (final b in bands) {
      if (b.days == days && b.kind == kind) return b;
    }
    return null;
  }

  List<String> get dayOrder {
    final seen = <String>[];
    for (final b in bands) {
      if (!seen.contains(b.days)) seen.add(b.days);
    }
    return seen;
  }

  static ParkTariff? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final unit = jsonIntSafe(m['unitMinutes'] ?? m['unit_minutes'], 30);
    final bandsRaw = m['bands'];
    if (bandsRaw is! List || bandsRaw.isEmpty) return null;
    final bands = <TariffBand>[];
    for (final row in bandsRaw) {
      if (row is! Map) continue;
      final b = TariffBand.tryParse(Map<String, dynamic>.from(row));
      if (b != null) bands.add(b);
    }
    if (bands.isEmpty) return null;
    final vals = <TariffValidation>[];
    final vRaw = m['validations'];
    if (vRaw is List) {
      for (final row in vRaw) {
        if (row is! Map) continue;
        final v = TariffValidation.tryParse(Map<String, dynamic>.from(row));
        if (v != null) vals.add(v);
      }
    }
    return ParkTariff(
      unitMinutes: unit == 60 ? 60 : 30,
      bands: bands,
      validations: vals,
      sourceName: '${m['sourceName'] ?? m['source_name'] ?? ''}'.trim().isEmpty
          ? null
          : '${m['sourceName'] ?? m['source_name']}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'unitMinutes': unitMinutes,
        'bands': bands.map((e) => e.toJson()).toList(),
        if (validations.isNotEmpty)
          'validations': validations.map((e) => e.toJson()).toList(),
        if (sourceName != null) 'sourceName': sourceName,
      };
}

class TariffBand {
  const TariffBand({
    required this.days,
    required this.kind,
    required this.start,
    required this.end,
    required this.amount,
  });

  /// mon-fri | sat-sun-ph | sun-fri | daily
  final String days;
  /// peak | offpeak
  final String kind;
  final String start;
  final String end;
  final double amount;

  String get daysLabel => switch (days) {
        'mon-fri' => '星期一至五',
        'sat-sun-ph' => '星期六、日及公眾假期',
        'sun-fri' => '星期日至五',
        'daily' => '每日',
        _ => days,
      };

  String get kindLabel => kind == 'offpeak' ? '非繁忙' : '繁忙時間';

  String get windowLabel {
    if (end.compareTo(start) < 0 || start == '23:00' && end == '07:00') {
      return '$start – 次日$end';
    }
    return '$start – $end';
  }

  static TariffBand? tryParse(Map<String, dynamic> m) {
    final amount = _num(m['amount']);
    if (amount == null) return null;
    final start = '${m['start'] ?? ''}'.trim();
    final end = '${m['end'] ?? ''}'.trim();
    if (start.isEmpty || end.isEmpty) return null;
    return TariffBand(
      days: '${m['days'] ?? 'daily'}',
      kind: '${m['kind'] ?? 'peak'}',
      start: start,
      end: end,
      amount: amount,
    );
  }

  Map<String, dynamic> toJson() => {
        'days': days,
        'kind': kind,
        'start': start,
        'end': end,
        'amount': amount,
      };
}

class TariffValidation {
  const TariffValidation({
    required this.days,
    required this.spendHkd,
    required this.freeHours,
    this.entryAfter,
  });

  final String days;
  final double spendHkd;
  final double freeHours;
  final String? entryAfter;

  String get daysLabel => switch (days) {
        'mon-fri' => '星期一至五',
        'sat-sun-ph' => '星期六、日及公眾假期',
        'sun-fri' => '星期日至五',
        'daily' => '每日',
        _ => days,
      };

  String get line {
    final spend = spendHkd.toStringAsFixed(0);
    final hrs = freeHours == freeHours.roundToDouble()
        ? freeHours.toStringAsFixed(0)
        : freeHours.toString();
    if (entryAfter != null && entryAfter!.isNotEmpty) {
      return '$daysLabel · $entryAfter 後入車，滿 HK\$$spend：免 $hrs 小時';
    }
    return '$daysLabel · 滿 HK\$$spend：免 $hrs 小時';
  }

  static TariffValidation? tryParse(Map<String, dynamic> m) {
    final spend = _num(m['spendHkd'] ?? m['spend']);
    final hours = _num(m['freeHours'] ?? m['free_hours']);
    if (spend == null || hours == null) return null;
    final after = '${m['entryAfter'] ?? m['entry_after'] ?? ''}'.trim();
    return TariffValidation(
      days: '${m['days'] ?? 'daily'}',
      spendHkd: spend,
      freeHours: hours,
      entryAfter: after.isEmpty ? null : after,
    );
  }

  Map<String, dynamic> toJson() => {
        'days': days,
        'spendHkd': spendHkd,
        'freeHours': freeHours,
        if (entryAfter != null) 'entryAfter': entryAfter,
      };
}

int jsonIntSafe(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

/// Reference record: 銅鑼灣時代廣場停車場 official tariff (2026-08).
Map<String, dynamic> timesSquareTariffJson() => {
      'unitMinutes': 30,
      'sourceName': '時代廣場停車場',
      'bands': [
        {
          'days': 'mon-fri',
          'kind': 'peak',
          'start': '07:00',
          'end': '23:00',
          'amount': 18,
        },
        {
          'days': 'mon-fri',
          'kind': 'offpeak',
          'start': '23:00',
          'end': '07:00',
          'amount': 8,
        },
        {
          'days': 'sat-sun-ph',
          'kind': 'peak',
          'start': '07:00',
          'end': '23:00',
          'amount': 19,
        },
        {
          'days': 'sat-sun-ph',
          'kind': 'offpeak',
          'start': '23:00',
          'end': '07:00',
          'amount': 8,
        },
      ],
      'validations': [
        {'days': 'mon-fri', 'spendHkd': 300, 'freeHours': 3},
        {
          'days': 'sun-fri',
          'spendHkd': 200,
          'freeHours': 3,
          'entryAfter': '16:00',
        },
        {'days': 'sat-sun-ph', 'spendHkd': 300, 'freeHours': 2},
      ],
    };
