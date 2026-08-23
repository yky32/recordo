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

  bool get hasPrice =>
      hourlyHkd != null || dailyHkd != null || nightHkd != null;

  String get priceSummary {
    if (hourlyHkd != null) return 'HK\$${hourlyHkd!.toStringAsFixed(0)}/時';
    if (dailyHkd != null) return 'HK\$${dailyHkd!.toStringAsFixed(0)}/日';
    if (nightHkd != null) return '夜泊 HK\$${nightHkd!.toStringAsFixed(0)}';
    return '未有收費';
  }

  String get freshnessLabel {
    final t = priceUpdatedAt;
    if (t == null) return '未有人更新';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前更新';
    if (d.inHours < 48) return '${d.inHours} 小時前更新';
    return '${d.inDays} 日前 · $ugcConfirms 人確認';
  }

  Park copyWith({
    double? hourlyHkd,
    double? dailyHkd,
    double? nightHkd,
    int? ugcConfirms,
    DateTime? priceUpdatedAt,
    String? source,
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
    );
  }
}
