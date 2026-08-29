import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_ev.dart';
import 'package:recordo/features/parks/park_tariff.dart';

void main() {
  test('ParkEv parses ifc kWh + idle, not as tariff', () {
    final ev = ParkEv.tryParse({
      'connectors': [
        {'kind': 'ac', 'kw': 7, 'count': 21},
        {'kind': 'dc', 'count': 7},
        {'kind': 'tesla', 'count': 3, 'access': 'tesla'},
      ],
      'billing': {
        'model': 'kwh',
        'amount': 3,
        'currency': 'HKD',
        'idleAfterMinutes': 15,
        'idlePerMinute': 5,
      },
    });
    expect(ev, isNotNull);
    expect(ev!.connectors.length, 3);
    expect(ev.billing.single.model, 'kwh');
    expect(ev.billing.single.line, contains('/ kWh'));
    expect(ParkTariff.tryParse(ev.toJson()), isNull);
  });

  test('bundledWithParking stays off the parking chip', () {
    final ev = ParkEv.tryParse({
      'connectors': [
        {'kind': 'ac', 'kw': 7},
      ],
      'billing': {
        'model': 'bundledWithParking',
        'amount': 17,
        'currency': 'HKD',
      },
    });
    final park = Park(
      id: 'kam',
      name: '錦上路',
      district: '元朗',
      lat: 22.43,
      lng: 114.06,
      hourlyHkd: 16,
      tariff: ParkTariff.tryParse({
        'unitMinutes': 30,
        'currency': 'HKD',
        'bands': [
          {
            'days': 'daily',
            'kind': 'peak',
            'start': '08:00',
            'end': '20:00',
            'amount': 8,
          },
        ],
      }),
      ev: ev,
    );
    expect(park.hasEvCharging, isTrue);
    expect(park.tariff!.weekdayPeakHourly, 16);
    expect(ev!.billing.single.line, contains('連充電'));
  });

  test('amenity-only (no billing) still hasCharging', () {
    final ev = ParkEv.tryParse({
      'connectors': [
        {'kind': 'dc', 'count': 30},
      ],
    });
    expect(ev!.hasCharging, isTrue);
    expect(ev.billing, isEmpty);
  });
}
