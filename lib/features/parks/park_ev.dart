import 'package:recordo/features/parks/park_tariff.dart';

/// EV charging sibling to [ParkTariff]. Never goes in `tariff.bands`
/// (would pollute the parking chip).
///
/// Amenity-only is valid (`connectors` without `billing`).
/// Official prices: `kwh` (ifc / SOUTHSIDE), `perSlice` (The Point 15 min),
/// `bundledWithParking` (MTR 泊車連充電).
class ParkEv {
  const ParkEv({
    this.connectors = const [],
    this.billing = const [],
  });

  final List<EvConnector> connectors;
  final List<EvBilling> billing;

  bool get hasCharging => connectors.isNotEmpty || billing.isNotEmpty;

  static ParkEv? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final connectors = <EvConnector>[];
    final cRaw = m['connectors'];
    if (cRaw is List) {
      for (final row in cRaw) {
        if (row is! Map) continue;
        final c = EvConnector.tryParse(Map<String, dynamic>.from(row));
        if (c != null) connectors.add(c);
      }
    }
    final billing = <EvBilling>[];
    final bRaw = m['billing'];
    if (bRaw is Map) {
      final b = EvBilling.tryParse(Map<String, dynamic>.from(bRaw));
      if (b != null) billing.add(b);
    } else if (bRaw is List) {
      for (final row in bRaw) {
        if (row is! Map) continue;
        final b = EvBilling.tryParse(Map<String, dynamic>.from(row));
        if (b != null) billing.add(b);
      }
    }
    if (connectors.isEmpty && billing.isEmpty) return null;
    return ParkEv(connectors: connectors, billing: billing);
  }

  Map<String, dynamic> toJson() => {
        if (connectors.isNotEmpty)
          'connectors': connectors.map((e) => e.toJson()).toList(),
        if (billing.length == 1)
          'billing': billing.first.toJson()
        else if (billing.isNotEmpty)
          'billing': billing.map((e) => e.toJson()).toList(),
      };
}

class EvConnector {
  const EvConnector({
    required this.kind,
    this.kw,
    this.count,
    this.access = 'all',
  });

  /// `ac` | `dc` | `tesla`
  final String kind;
  final double? kw;
  final int? count;

  /// `all` | `tesla` | `porsche` | `ccs2`
  final String access;

  static const kinds = {'ac', 'dc', 'tesla'};
  static const accesses = {'all', 'tesla', 'porsche', 'ccs2'};

  String get kindLabel => switch (kind) {
        'ac' => '中充 AC',
        'dc' => '快充 DC',
        'tesla' => 'Tesla',
        _ => kind,
      };

  String get line {
    final bits = <String>[kindLabel];
    if (kw != null) bits.add('${kw!.toString().replaceAll(RegExp(r"\.0$"), "")} kW');
    if (count != null) bits.add('$count 個');
    if (access != 'all') bits.add(access == 'ccs2' ? 'CCS2' : access);
    return bits.join(' · ');
  }

  static EvConnector? tryParse(Map<String, dynamic> m) {
    final kind = '${m['kind'] ?? ''}'.trim().toLowerCase();
    if (!kinds.contains(kind)) return null;
    final accessRaw = '${m['access'] ?? 'all'}'.trim().toLowerCase();
    final access = accesses.contains(accessRaw) ? accessRaw : 'all';
    return EvConnector(
      kind: kind,
      kw: _num(m['kw']),
      count: _int(m['count']),
      access: access,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (kw != null) 'kw': kw,
        if (count != null) 'count': count,
        if (access != 'all') 'access': access,
      };
}

class EvBilling {
  const EvBilling({
    required this.model,
    required this.amount,
    this.currency = 'HKD',
    this.kind,
    this.kw,
    this.sliceMinutes,
    this.idleAfterMinutes,
    this.idlePerMinute,
  });

  /// `kwh` | `perSlice` | `bundledWithParking`
  final String model;
  final double amount;
  final String currency;
  final String? kind;
  final double? kw;
  final int? sliceMinutes;
  final int? idleAfterMinutes;
  final double? idlePerMinute;

  static const models = {'kwh', 'perSlice', 'bundledWithParking'};

  String get line {
    final money = moneyLabel(amount, currency);
    final core = switch (model) {
      'kwh' => '$money / kWh',
      'perSlice' =>
        '$money / ${sliceMinutes ?? 15} 分',
      'bundledWithParking' => '連充電 $money',
      _ => money,
    };
    final idle = idleAfterMinutes == null
        ? ''
        : ' · $idleAfterMinutes 分後逾時${idlePerMinute == null ? '' : ' ${moneyLabel(idlePerMinute!, currency)}/分'}';
    final which = kind == null ? '' : '（${kind == 'ac' ? 'AC' : kind == 'dc' ? 'DC' : kind}）';
    return '$core$which$idle';
  }

  static EvBilling? tryParse(Map<String, dynamic> m) {
    final model = '${m['model'] ?? ''}'.trim();
    if (!models.contains(model)) return null;
    final amount = _num(m['amount']);
    if (amount == null || amount < 0) return null;
    var currency = '${m['currency'] ?? 'HKD'}'.trim().toUpperCase();
    if (currency.length != 3) currency = 'HKD';
    return EvBilling(
      model: model,
      amount: amount,
      currency: currency,
      kind: m['kind'] == null ? null : '${m['kind']}'.trim().toLowerCase(),
      kw: _num(m['kw']),
      sliceMinutes: _int(m['sliceMinutes'] ?? m['slice_minutes']),
      idleAfterMinutes: _int(m['idleAfterMinutes'] ?? m['idle_after_minutes']),
      idlePerMinute: _num(m['idlePerMinute'] ?? m['idle_per_minute']),
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'amount': amount,
        'currency': currency,
        if (kind != null) 'kind': kind,
        if (kw != null) 'kw': kw,
        if (sliceMinutes != null) 'sliceMinutes': sliceMinutes,
        if (idleAfterMinutes != null) 'idleAfterMinutes': idleAfterMinutes,
        if (idlePerMinute != null) 'idlePerMinute': idlePerMinute,
      };
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

