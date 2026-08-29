import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_rank.dart';

Park _p(String id, {double? hourly}) => Park(
      id: id,
      name: id,
      district: '測試',
      lat: 22.3,
      lng: 114.17,
      hourlyHkd: hourly,
    );

void main() {
  test('pinSelectedToFront lifts selected out of rest to row 0', () {
    final kam = _p('kam', hourly: 16);
    final far = _p('sha-tin', hourly: 22);
    final out = pinSelectedToFront(
      featured: [far],
      rest: [kam],
      selectedId: 'kam',
    );
    expect(out.featured.first.id, 'kam');
    expect(out.featured.map((e) => e.id), ['kam', 'sha-tin']);
    expect(out.rest, isEmpty);
  });

  test('pinSelectedToFront uses fallback when missing from both lists', () {
    final kam = _p('kam', hourly: 16);
    final far = _p('sha-tin', hourly: 22);
    final out = pinSelectedToFront(
      featured: [far],
      rest: const [],
      selectedId: 'kam',
      fallback: kam,
    );
    expect(out.featured.first.id, 'kam');
    expect(out.featured[1].id, 'sha-tin');
  });
}
