import 'package:recordo/features/parks/park_tariff.dart';

/// On-street TD meter group (one street + hours class). Not a [Park].
class MeterStreet {
  const MeterStreet({
    required this.id,
    required this.name,
    required this.district,
    required this.street,
    required this.lat,
    required this.lng,
    required this.hoursClass,
    this.spacesCar = 0,
    this.tariff,
  });

  final String id;
  final String name;
  final String district;
  final String street;
  final double lat;
  final double lng;
  final String hoursClass;
  final int spacesCar;
  final ParkTariff? tariff;

  String get chipLabel {
    final bands = tariff?.bands ?? const [];
    final amt = bands.isEmpty ? 4.0 : bands.first.amount;
    return '${moneyLabel(amt, tariff?.currency ?? 'HKD')}/15分';
  }

  static MeterStreet? tryParse(Map<String, dynamic> m) {
    final lat = _d(m['lat']);
    final lng = _d(m['lng']);
    if (lat == null || lng == null) return null;
    final id = '${m['id'] ?? ''}';
    if (id.isEmpty) return null;
    return MeterStreet(
      id: id,
      name: '${m['name'] ?? '咪錶'}',
      district: '${m['district'] ?? ''}',
      street: '${m['street'] ?? ''}',
      lat: lat,
      lng: lng,
      hoursClass: '${m['hoursClass'] ?? m['hours_class'] ?? ''}',
      spacesCar: _i(m['spacesCar'] ?? m['spaces_car']),
      tariff: ParkTariff.tryParse(m['tariff']),
    );
  }

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
