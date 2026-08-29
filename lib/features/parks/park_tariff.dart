/// HK mall / car-park tariff. Times Square is the reference shape:
/// billed per 30 min, weekday vs weekend+PH, peak vs overnight, mall validation.
class ParkTariff {
  const ParkTariff({
    required this.unitMinutes,
    required this.bands,
    this.validations = const [],
    this.sourceName,
    this.currency = 'HKD',
  });

  /// 30 = 半小時 (Times Square / most malls). 60 = 每小時.
  final int unitMinutes;
  final List<TariffBand> bands;
  final List<TariffValidation> validations;
  final String? sourceName;
  /// ISO 4217. Never bake currency into JSON keys (`spend` not `spendHkd`).
  final String currency;

  String get unitLabel => unitMinutes == 30 ? '半小時' : '小時';

  double get _perHourFactor => 60 / unitMinutes;

  /// Chip: first weekday peak rate, never a day package.
  double? get weekdayPeakHourly {
    final b = _band(days: 'mon-fri', kind: 'peak') ??
        _band(days: 'mon-sat', kind: 'peak') ??
        _band(days: 'mon-thu', kind: 'peak') ??
        _firstPeak;
    if (b == null) return null;
    return b.amount * _perHourFactor;
  }

  TariffBand? get _firstPeak {
    for (final b in bands) {
      if (b.kind == 'peak') return b;
    }
    return null;
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
      currency: _currencyCode(m['currency']),
    );
  }

  Map<String, dynamic> toJson() => {
        'unitMinutes': unitMinutes,
        'currency': currency,
        'bands': bands.map((e) => e.toJson()).toList(),
        if (validations.isNotEmpty)
          'validations': validations.map((e) => e.toJson()).toList(),
        if (sourceName != null) 'sourceName': sourceName,
      };
}

String tariffDaysLabel(String days) => switch (days) {
      'mon-thu' => '星期一至四（公眾假期除外）',
      'mon-fri' => '星期一至五',
      'mon-sat' => '星期一至六（公眾假期除外）',
      'fri-sun-ph' => '星期五、六、日及公眾假期',
      'sat-sun-ph' => '星期六、日及公眾假期',
      'sun-ph' => '星期日及公眾假期',
      'sun-fri' => '星期日至五',
      'daily' => '每日',
      _ => days,
    };

class TariffBand {
  const TariffBand({
    required this.days,
    required this.kind,
    required this.start,
    required this.end,
    required this.amount,
  });

  /// mon-thu | mon-fri | mon-sat | fri-sun-ph | sat-sun-ph | sun-ph | sun-fri | daily
  final String days;
  /// peak | offpeak | day (flat package, not per unit)
  final String kind;
  final String start;
  final String end;
  final double amount;

  String get daysLabel => tariffDaysLabel(days);

  String get kindLabel => switch (kind) {
        'offpeak' => '非繁忙',
        'day' => '日泊',
        _ => '繁忙時間',
      };

  bool get isPackage => kind == 'day';

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
    required this.spend,
    required this.freeHours,
    this.entryAfter,
  });

  final String days;
  final double spend;
  final double freeHours;
  final String? entryAfter;

  String get daysLabel => tariffDaysLabel(days);

  String line({String currency = 'HKD'}) {
    final hrs = freeHours == freeHours.roundToDouble()
        ? freeHours.toStringAsFixed(0)
        : freeHours.toString();
    final money = moneyLabel(spend, currency);
    if (entryAfter != null && entryAfter!.isNotEmpty) {
      return '$daysLabel · $entryAfter 後入車，滿 $money：免 $hrs 小時';
    }
    return '$daysLabel · 滿 $money：免 $hrs 小時';
  }

  static TariffValidation? tryParse(Map<String, dynamic> m) {
    final spend = _num(m['spend'] ?? m['spendHkd']);
    final hours = _num(m['freeHours'] ?? m['free_hours']);
    if (spend == null || hours == null) return null;
    final after = '${m['entryAfter'] ?? m['entry_after'] ?? ''}'.trim();
    return TariffValidation(
      days: '${m['days'] ?? 'daily'}',
      spend: spend,
      freeHours: hours,
      entryAfter: after.isEmpty ? null : after,
    );
  }

  Map<String, dynamic> toJson() => {
        'days': days,
        'spend': spend,
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

String _currencyCode(dynamic raw) {
  final s = '${raw ?? ''}'.trim().toUpperCase();
  if (s == 'TWD' || s == 'NTD' || s == 'NT\$' || s == 'NTD') return 'TWD';
  if (s == 'HKD' || s.isEmpty) return 'HKD';
  if (s.length == 3) return s;
  return 'HKD';
}

/// Amount only. Currency is a sibling field, never in the key.
String moneyLabel(num amount, [String currency = 'HKD']) {
  final n = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toString();
  return switch (currency.toUpperCase()) {
    'TWD' => 'NT\$$n',
    'HKD' => 'HK\$$n',
    _ => '$currency $n',
  };
}

/// Reference record: 銅鑼灣時代廣場停車場 official tariff (2026-08).
Map<String, dynamic> timesSquareTariffJson() => {
      'unitMinutes': 30,
      'currency': 'HKD',
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
        {'days': 'mon-fri', 'spend': 300, 'freeHours': 3},
        {
          'days': 'sun-fri',
          'spend': 200,
          'freeHours': 3,
          'entryAfter': '16:00',
        },
        {'days': 'sat-sun-ph', 'spend': 300, 'freeHours': 2},
      ],
    };
