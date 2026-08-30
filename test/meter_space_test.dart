import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/meter_space.dart';

void main() {
  test('1794A parses LPP 30 and 15-minute fee', () {
    final m = MeterSpace.tryParse({
      'id': '1794A',
      'district': '灣仔',
      'subDistrict': '軒尼詩',
      'street': '譚臣道',
      'section': '莊士敦道',
      'lat': 22.27709,
      'lng': 114.17108,
      'vehicleType': 'A',
      'lpp': 30,
      'timeUnit': 15,
      'paymentUnit': 4,
    });
    expect(m, isNotNull);
    expect(m!.placeLine, '譚臣道 - 莊士敦道');
    expect(m.lppLabel, '最長停泊時間 30 分鐘');
    expect(m.feeLabel, '15 分鐘 - HK\$4');
    expect(m.vehicleLabel, '任何車輛');
  });

  test('occupancy CSV vacant vs occupied vs NA', () {
    const csv = 'ParkingSpaceId,ParkingMeterStatus,OccupancyStatus,OccupancyDateChanged\n'
        '1794A,N,V,08/30/2026 01:16:41 PM\n'
        '1794B,N,O,08/30/2026 01:16:41 PM\n'
        '1000A,NA,O,08/30/2026 01:16:41 PM\n';
    final map = parseMeterOccupancyCsv(csv);
    expect(map['1794A']!.status, MeterBayStatus.vacant);
    expect(map['1794B']!.status, MeterBayStatus.occupied);
    expect(map['1000A']!.status, MeterBayStatus.suspended);
  });
}
