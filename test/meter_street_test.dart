import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/meter_street.dart';

void main() {
  test('skips meters without coordinates', () {
    expect(
      MeterStreet.tryParse({
        'id': 'td:元朗:錦田公路:D',
        'name': '咪錶 · 錦田公路',
        'district': '元朗',
        'street': '錦田公路',
      }),
      isNull,
    );
  });

  test('chip is per 15 min not hourly', () {
    final m = MeterStreet.tryParse({
      'id': 'td:元朗:錦田公路:D',
      'name': '咪錶 · 錦田公路',
      'district': '元朗',
      'street': '錦田公路',
      'lat': 22.44,
      'lng': 114.06,
      'hoursClass': 'D',
      'spacesCar': 12,
      'tariff': {
        'unitMinutes': 15,
        'currency': 'HKD',
        'bands': [
          {'days': 'mon-sat', 'kind': 'peak', 'amount': 4},
        ],
      },
    });
    expect(m!.chipLabel, 'HK\$4/15分');
  });
}
