import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/hk_districts.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/price_verification.dart';

void main() {
  test('clamp name and district', () {
    expect(clampParkName('地'), isNull);
    expect(clampParkName(' 地庫停車場 '), '地庫停車場');
    expect(clampDistrict('灣仔/銅鑼灣'), isNull);
    expect(clampDistrict('銅鑼灣'), '銅鑼灣');
  });

  test('official parks cannot edit identity', () {
    const official = Park(
      id: 'v_walk',
      name: 'V Walk 停車場',
      district: '深水埗',
      lat: 22.3,
      lng: 114.1,
      hourlyHkd: 24,
      priceVerificationStatus: PriceVerificationStatus.verified,
      priceProvenance: PriceProvenance.operator,
    );
    expect(official.canEditIdentity, isFalse);

    const osm = Park(
      id: 'osm:1',
      name: '地庫停車場',
      district: '灣仔/銅鑼灣',
      lat: 22.28,
      lng: 114.18,
      source: 'osm',
    );
    expect(osm.canEditIdentity, isTrue);
  });
}
