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

  bool get hasPrice =>
      hourlyHkd != null || dailyHkd != null || nightHkd != null;

  bool get hasPriceNote => priceNote.trim().isNotEmpty;

  /// List / hero line — median-style display with report count when known.
  String get priceSummary {
    if (hourlyHkd != null) {
      final x = hourlyHkd!.toStringAsFixed(0);
      if (ugcConfirms >= 2) return '約 HK\$$x/時 · $ugcConfirms 人';
      if (ugcConfirms == 1) return '約 HK\$$x/時 · 1 人';
      return '約 HK\$$x/時';
    }
    if (dailyHkd != null) {
      final x = dailyHkd!.toStringAsFixed(0);
      if (ugcConfirms >= 2) return '約 HK\$$x/日 · $ugcConfirms 人';
      return '約 HK\$$x/日';
    }
    if (nightHkd != null) {
      return '夜泊約 HK\$${nightHkd!.toStringAsFixed(0)}';
    }
    return '未有收費';
  }

  /// Trust copy under the price.
  String get trustLabel {
    if (!hasPrice) return '未有人更新 · 你可以做第一個';
    if (ugcConfirms >= 8) return '較多司機報告 · 中位參考價';
    if (ugcConfirms >= 3) return '$ugcConfirms 人報告 · 中位參考價';
    if (ugcConfirms == 2) return '2 人報告 · 仍可能有偏差';
    if (ugcConfirms == 1) return '只有 1 人報告';
    return freshnessLabel;
  }

  /// Optional hint for a 1-report price (shown as tooltip).
  String? get trustTooltip {
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
  }) {
    return Park(
      id: id,
      name: name,
      district: district,
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
    );
  }
}
