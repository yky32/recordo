import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/td_vacancy.dart';

void main() {
  test('parses HOURLY private-car vacancy', () {
    final v = hourlyPrivateVacancy({
      'park_id': 'tdc1',
      'vehicle_type': [
        {
          'type': 'P',
          'service_category': [
            {'category': 'HOURLY', 'vacancy': 7},
          ],
        },
      ],
    });
    expect(v, 7);
  });

  test('0 is full, -1 is no data', () {
    expect(const TdHourlyVacancy(
      parkId: 'a',
      nameTc: 'x',
      lat: 22,
      lng: 114,
      vacancy: 0,
    ).label, '滿');
    expect(const TdHourlyVacancy(
      parkId: 'a',
      nameTc: 'x',
      lat: 22,
      lng: 114,
      vacancy: -1,
    ).label, '空位無數據');
    expect(const TdHourlyVacancy(
      parkId: 'a',
      nameTc: 'x',
      lat: 22,
      lng: 114,
      vacancy: 3,
    ).label, '有位 3');
  });

  test('matchTdToParks snaps within 80m, skips far lots', () {
    final near = Park(
      id: 'kam',
      name: '錦上路',
      district: '元朗',
      lat: 22.43374,
      lng: 114.06285,
    );
    final live = [
      const TdHourlyVacancy(
        parkId: 'td-kam',
        nameTc: '錦上路',
        lat: 22.43380,
        lng: 114.06290,
        vacancy: 4,
      ),
      const TdHourlyVacancy(
        parkId: 'td-far',
        nameTc: '尖沙咀',
        lat: 22.297,
        lng: 114.174,
        vacancy: 20,
      ),
    ];
    final mapped = matchTdToParks(parks: [near], live: live);
    expect(mapped['kam']?.parkId, 'td-kam');
    expect(mapped['kam']?.vacancy, 4);
    expect(mapped.length, 1);
  });
}
