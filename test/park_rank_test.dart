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

  test('with GPS, 19km K11 sorts after 114m 錦上路', () {
    const kamLat = 22.435;
    const kamLng = 114.064;
    final kam = Park(
      id: 'kam',
      name: '錦上路',
      district: '元朗',
      lat: kamLat,
      lng: kamLng,
      hourlyHkd: 16,
    );
    final k11 = Park(
      id: 'k11',
      name: 'K11 Art Mall',
      district: '尖沙咀',
      lat: 22.297,
      lng: 114.174,
      hourlyHkd: 39,
    );
    final cmp = compareParksForDisplay(
      kam,
      k11,
      centerLat: kamLat,
      centerLng: kamLng,
    );
    expect(cmp, lessThan(0));
  });

  test('sortParksForDisplay is distance-first with one geodesic per park', () {
    const kamLat = 22.435;
    const kamLng = 114.064;
    final kam = Park(
      id: 'kam',
      name: '錦上路',
      district: '元朗',
      lat: kamLat,
      lng: kamLng,
      hourlyHkd: 16,
    );
    final k11 = Park(
      id: 'k11',
      name: 'K11 Art Mall',
      district: '尖沙咀',
      lat: 22.297,
      lng: 114.174,
      hourlyHkd: 39,
    );
    final sorted = sortParksForDisplay(
      [k11, kam],
      centerLat: kamLat,
      centerLng: kamLng,
    );
    expect(sorted.first.id, 'kam');
    expect(sorted.last.id, 'k11');
  });

  test('splitFeaturedRest keeps nearby priced, not only wedge', () {
    final near = _p('yoho', hourly: 20);
    final farWedge = Park(
      id: 'k11',
      name: 'K11',
      district: '尖沙咀',
      lat: 22.297,
      lng: 114.174,
      hourlyHkd: 39,
    );
    final out = splitFeaturedRest([near, farWedge], searching: false);
    expect(out.featured.map((e) => e.id), ['yoho', 'k11']);
  });
}
