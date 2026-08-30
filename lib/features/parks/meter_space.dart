enum MeterBayStatus { vacant, occupied, suspended }

MeterBayStatus meterBayStatus({
  required String meterStatus,
  required String occupancy,
}) {
  final ms = meterStatus.trim().toUpperCase();
  if (ms == 'NA') return MeterBayStatus.suspended;
  if (occupancy.trim().toUpperCase() == 'V') return MeterBayStatus.vacant;
  return MeterBayStatus.occupied;
}

class MeterOccupancy {
  const MeterOccupancy({
    required this.id,
    required this.status,
  });

  final String id;
  final MeterBayStatus status;
}

class MeterSpace {
  const MeterSpace({
    required this.id,
    required this.district,
    required this.street,
    required this.lat,
    required this.lng,
    this.poleId,
    this.subDistrict = '',
    this.section = '',
    this.vehicleType = 'A',
    this.lpp,
    this.hoursClass = '',
    this.timeUnit = 15,
    this.paymentUnit = 4,
  });

  final String id;
  final String? poleId;
  final String district;
  final String subDistrict;
  final String street;
  final String section;
  final double lat;
  final double lng;
  final String vehicleType;
  final int? lpp;
  final String hoursClass;
  final int timeUnit;
  final double paymentUnit;

  String get placeLine {
    final a = street.trim();
    final b = section.trim();
    if (a.isEmpty) return district;
    if (b.isEmpty || b == a) return a;
    return '$a - $b';
  }

  String get vehicleLabel {
    switch (vehicleType.toUpperCase()) {
      case 'G':
        return '貨車';
      case 'C':
        return '私家車';
      default:
        return '任何車輛';
    }
  }

  String get lppLabel {
    final m = lpp;
    if (m == null || m <= 0) return '最長停泊未有數據';
    if (m % 60 == 0) return '最長停泊時間 ${m ~/ 60} 小時';
    return '最長停泊時間 $m 分鐘';
  }

  String get feeLabel {
    final amt = paymentUnit == paymentUnit.roundToDouble()
        ? paymentUnit.toInt().toString()
        : paymentUnit.toString();
    return '$timeUnit 分鐘 - HK\$$amt';
  }

  static MeterSpace? tryParse(Map<String, dynamic> m) {
    final id = '${m['id'] ?? ''}'.trim();
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    if (id.isEmpty || lat == null || lng == null) return null;
    if (lat.abs() < 0.01 && lng.abs() < 0.01) return null;
    return MeterSpace(
      id: id,
      poleId: m['poleId'] as String?,
      district: '${m['district'] ?? ''}',
      subDistrict: '${m['subDistrict'] ?? ''}',
      street: '${m['street'] ?? ''}',
      section: '${m['section'] ?? ''}',
      lat: lat,
      lng: lng,
      vehicleType: '${m['vehicleType'] ?? 'A'}',
      lpp: (m['lpp'] as num?)?.toInt(),
      hoursClass: '${m['hoursClass'] ?? ''}',
      timeUnit: (m['timeUnit'] as num?)?.toInt() ?? 15,
      paymentUnit: (m['paymentUnit'] as num?)?.toDouble() ?? 4,
    );
  }
}

/// Occupancy CSV: ParkingSpaceId,ParkingMeterStatus,OccupancyStatus,...
Map<String, MeterOccupancy> parseMeterOccupancyCsv(String raw) {
  final out = <String, MeterOccupancy>{};
  final lines = raw.split(RegExp(r'\r?\n'));
  var start = 0;
  if (lines.isNotEmpty && lines.first.toLowerCase().contains('parkingspaceid')) {
    start = 1;
  }
  for (var i = start; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final cols = line.split(',');
    if (cols.length < 3) continue;
    final id = cols[0].trim();
    if (id.isEmpty) continue;
    out[id] = MeterOccupancy(
      id: id,
      status: meterBayStatus(meterStatus: cols[1], occupancy: cols[2]),
    );
  }
  return out;
}
