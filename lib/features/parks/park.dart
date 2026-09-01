import 'package:recordo/features/parks/price_verification.dart';
import 'package:recordo/features/parks/park_tariff.dart';
import 'package:recordo/features/parks/park_ev.dart';

/// OSM often names unnamed lots `停車場 (underground)` — last letter clips in
/// the list, and English type tags read poorly. Map to short HK copy.
String prettyParkName(String raw) {
  final s = raw.trim();
  final m = RegExp(
    r'^(.*?)(?:\s*[\(（]\s*(underground|multi-storey|multistorey|multi_storey|rooftop|surface)\s*[\)）])\s*$',
    caseSensitive: false,
  ).firstMatch(s);
  if (m == null) return s;
  const kinds = {
    'underground': '地庫',
    'multi-storey': '多層',
    'multistorey': '多層',
    'multi_storey': '多層',
    'rooftop': '天台',
    'surface': '露天',
  };
  final kind = kinds[m.group(2)!.toLowerCase()]!;
  final base = m.group(1)!.trim();
  if (base.isEmpty ||
      base == '停車場' ||
      base.toLowerCase() == 'parking' ||
      base.toLowerCase() == 'car park') {
    return '$kind停車場';
  }
  if (base.endsWith('停車場') || base.endsWith('停车场')) {
    return '$base（$kind）';
  }
  return '$base（$kind）';
}

int jsonInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

double? jsonDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

class Park {
  const Park({
    required this.id,
    required this.name,
    required this.district,
    required this.lat,
    required this.lng,
    this.hourlyHkd,
    this.dailyHkd,
    this.nightHkd,
    this.heightM,
    this.ugcConfirms = 0,
    this.priceUpdatedAt,
    this.source = 'seed',
    this.priceNote = '',
    this.priceVerificationStatus = PriceVerificationStatus.unverified,
    this.priceVerifiedAt,
    this.priceProvenance = PriceProvenance.unknown,
    this.tariff,
    this.ev,
    this.address = '',
    this.tdParkId = '',
  });

  final String id;
  final String name;
  final String district;
  final double lat;
  final double lng;
  final double? hourlyHkd;
  final double? dailyHkd;
  final double? nightHkd;
  final double? heightM;
  final int ugcConfirms;
  final DateTime? priceUpdatedAt;
  final String source;
  /// Free-text rule, e.g. 「首小時 $30 · 之後每半鐘 $15」
  final String priceNote;
  final PriceVerificationStatus priceVerificationStatus;
  final DateTime? priceVerifiedAt;
  final PriceProvenance priceProvenance;
  final ParkTariff? tariff;
  final ParkEv? ev;

  /// Full street address. Search + detail. Empty until catalog has it.
  final String address;

  /// TD `hk-td-tis_5` park_id. Vacancy joins on this, not 80m guess.
  final String tdParkId;

  bool get hasPrice =>
      hourlyHkd != null ||
      dailyHkd != null ||
      nightHkd != null ||
      tariff != null;

  bool get hasPriceNote => priceNote.trim().isNotEmpty;

  bool get isVerifiedPrice =>
      hasPrice && priceVerificationStatus == PriceVerificationStatus.verified;

  bool get isOperatorOfficial =>
      isVerifiedPrice && priceProvenance == PriceProvenance.operator;

  /// Public UGC may fix OSM junk names. Official malls stay locked.
  bool get canEditIdentity => !isOperatorOfficial;

  bool get isSeedDemoPrice =>
      hasPrice &&
      !isVerifiedPrice &&
      (priceProvenance == PriceProvenance.seed ||
          source == 'seed' ||
          source == 'seed+osm');

  bool get hasUgcReports => ugcConfirms > 0;

  bool get hasEvCharging => ev?.hasCharging == true;

  bool get showAsMapPriceChip => isVerifiedPrice || hasUgcReports;

  String get verifiedTag =>
      priceProvenance == PriceProvenance.operator ? '官方牌價' : '場內核實';

  /// Short badge for list / map chrome.
  String get priceBadgeLabel {
    if (!hasPrice) return '未有價';
    if (isVerifiedPrice) {
      if (priceProvenance == PriceProvenance.operator) return '官方牌價';
      return '場內核實';
    }
    if (hasUgcReports) return '司機報價';
    if (isSeedDemoPrice) return '未核實';
    return '未有價';
  }

  String get currency => tariff?.currency ?? 'HKD';

  /// Amount only — list uses this; tick / ? carry trust, not the words.
  String get priceAmountLabel {
    if (hourlyHkd != null) {
      return '約 ${moneyLabel(hourlyHkd!, currency)}/時';
    }
    if (dailyHkd != null) {
      return '約 ${moneyLabel(dailyHkd!, currency)}/日';
    }
    if (nightHkd != null) {
      return '夜泊約 ${moneyLabel(nightHkd!, currency)}';
    }
    return '未有收費';
  }

  /// List / hero line — median-style display with report count when known.
  String get priceSummary {
    if (hourlyHkd != null) {
      final x = moneyLabel(hourlyHkd!, currency);
      if (isVerifiedPrice) return '約 $x/時 · $verifiedTag';
      if (ugcConfirms >= 2) return '約 $x/時 · $ugcConfirms 人';
      if (ugcConfirms == 1) return '約 $x/時 · 1 人';
      if (isSeedDemoPrice) return '約 $x/時 · 未核實';
      return '約 $x/時';
    }
    if (dailyHkd != null) {
      final x = moneyLabel(dailyHkd!, currency);
      if (isVerifiedPrice) return '約 $x/日 · 場內核實';
      if (ugcConfirms >= 2) return '約 $x/日 · $ugcConfirms 人';
      if (isSeedDemoPrice) return '約 $x/日 · 未核實';
      return '約 $x/日';
    }
    if (nightHkd != null) {
      final base = '夜泊約 ${moneyLabel(nightHkd!, currency)}';
      if (isVerifiedPrice) return '$base · 場內核實';
      if (isSeedDemoPrice) return '$base · 未核實';
      return base;
    }
    return '未有收費';
  }

  /// Trust copy under the price.
  String get trustLabel {
    if (!hasPrice) return '未有人更新 · 你可以做第一個';
    if (isVerifiedPrice) {
      final when = priceVerifiedAt;
      if (priceProvenance == PriceProvenance.operator) {
        return tariff != null
            ? '官方牌價 · 按${tariff!.unitLabel}計'
            : '官方牌價';
      }
      if (when != null) {
        final d = DateTime.now().difference(when);
        if (d.inDays < 30) return '場內核實 · ${d.inDays == 0 ? '今日' : '${d.inDays} 日前'}核對';
      }
      return '場內核實 · 閘口牌價';
    }
    if (isSeedDemoPrice) return '示範價 · 未核實 · 歡迎報價';
    if (ugcConfirms >= 8) return '較多司機報告 · 中位參考價';
    if (ugcConfirms >= 3) return '$ugcConfirms 人報告 · 中位參考價';
    if (ugcConfirms == 2) return '2 人報告 · 仍可能有偏差';
    if (ugcConfirms == 1) return '只有 1 人報告';
    return freshnessLabel;
  }

  /// Optional hint for a 1-report price (shown as tooltip).
  String? get trustTooltip {
    if (isSeedDemoPrice) return '示範價，以閘口為準';
    if (hasPrice && ugcConfirms == 1) return '僅供參考';
    return null;
  }

  /// Time-only freshness, e.g. `25 小時前更新`. Empty if never updated.
  String get freshnessAgoLabel {
    final t = priceUpdatedAt;
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前更新';
    if (d.inHours < 48) return '${d.inHours} 小時前更新';
    return '${d.inDays} 日前更新';
  }

  String get freshnessLabel {
    final ago = freshnessAgoLabel;
    if (ago.isEmpty) {
      if (isSeedDemoPrice) return '示範價 · 未核實';
      return ugcConfirms > 0 ? '$ugcConfirms 人報告' : '未有人更新';
    }
    final who = ugcConfirms > 0 ? ' · $ugcConfirms 人' : '';
    return '$ago$who';
  }

  Park copyWith({
    double? hourlyHkd,
    double? dailyHkd,
    double? nightHkd,
    int? ugcConfirms,
    DateTime? priceUpdatedAt,
    String? source,
    String? priceNote,
    PriceVerificationStatus? priceVerificationStatus,
    DateTime? priceVerifiedAt,
    PriceProvenance? priceProvenance,
    ParkTariff? tariff,
    ParkEv? ev,
    String? address,
    String? tdParkId,
    String? name,
    String? district,
    bool clearPriceVerifiedAt = false,
  }) {
    return Park(
      id: id,
      name: name ?? this.name,
      district: district ?? this.district,
      lat: lat,
      lng: lng,
      hourlyHkd: hourlyHkd ?? this.hourlyHkd,
      dailyHkd: dailyHkd ?? this.dailyHkd,
      nightHkd: nightHkd ?? this.nightHkd,
      heightM: heightM,
      ugcConfirms: ugcConfirms ?? this.ugcConfirms,
      priceUpdatedAt: priceUpdatedAt ?? this.priceUpdatedAt,
      source: source ?? this.source,
      priceNote: priceNote ?? this.priceNote,
      priceVerificationStatus:
          priceVerificationStatus ?? this.priceVerificationStatus,
      priceVerifiedAt: clearPriceVerifiedAt
          ? null
          : (priceVerifiedAt ?? this.priceVerifiedAt),
      priceProvenance: priceProvenance ?? this.priceProvenance,
      tariff: tariff ?? this.tariff,
      ev: ev ?? this.ev,
      address: address ?? this.address,
      tdParkId: tdParkId ?? this.tdParkId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'district': district,
        'lat': lat,
        'lng': lng,
        'hourlyHkd': hourlyHkd,
        'dailyHkd': dailyHkd,
        'nightHkd': nightHkd,
        'heightM': heightM,
        'ugcConfirms': ugcConfirms,
        'priceUpdatedAt': priceUpdatedAt?.toUtc().toIso8601String(),
        'source': source,
        'priceNote': priceNote,
        'priceVerificationStatus':
            verificationStatusToJson(priceVerificationStatus),
        'priceVerifiedAt': priceVerifiedAt?.toUtc().toIso8601String(),
        'priceProvenance': priceProvenanceToJson(priceProvenance),
        if (tariff != null) 'tariff': tariff!.toJson(),
        if (ev != null) 'ev': ev!.toJson(),
        if (address.isNotEmpty) 'address': address,
        if (tdParkId.isNotEmpty) 'tdParkId': tdParkId,
      };

  factory Park.fromJson(Map<String, dynamic> m) {
    final updated = m['priceUpdatedAt'] ?? m['price_updated_at'];
    final verified = m['priceVerifiedAt'] ?? m['price_verified_at'];
    return Park(
      id: m['id'] as String? ?? 'unknown',
      name: prettyParkName(m['name'] as String? ?? '停車場'),
      district: m['district'] as String? ?? '香港',
      lat: jsonDouble(m['lat']) ?? 22.3,
      lng: jsonDouble(m['lng']) ?? 114.17,
      hourlyHkd: jsonDouble(m['hourlyHkd'] ?? m['hourly_hkd']),
      dailyHkd: jsonDouble(m['dailyHkd'] ?? m['daily_hkd']),
      nightHkd: jsonDouble(m['nightHkd'] ?? m['night_hkd']),
      heightM: jsonDouble(m['heightM'] ?? m['height_m']),
      ugcConfirms: jsonInt(m['ugcConfirms'] ?? m['ugc_confirms']),
      priceUpdatedAt: updated != null ? DateTime.tryParse('$updated') : null,
      source: m['source'] as String? ?? 'osm',
      priceNote: '${m['priceNote'] ?? m['price_note'] ?? ''}'.trim(),
      priceVerificationStatus: parseVerificationStatus(
        m['priceVerificationStatus'] ?? m['price_verification_status'],
      ),
      priceVerifiedAt:
          verified != null ? DateTime.tryParse('$verified') : null,
      priceProvenance: parsePriceProvenance(
        m['priceProvenance'] ?? m['price_provenance'],
      ),
      tariff: ParkTariff.tryParse(m['tariff']),
      ev: ParkEv.tryParse(m['ev']),
      address: '${m['address'] ?? ''}'.trim(),
      tdParkId: '${m['tdParkId'] ?? m['td_park_id'] ?? ''}'.trim(),
    );
  }
}
