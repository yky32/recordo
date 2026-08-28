import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/core/config/hk_wedge.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_rank.dart';
import 'package:recordo/features/parks/price_verification.dart';

void main() {
  test('seed parks have zero fake confirms and unverified provenance', () {
    for (final p in hkSeedParks) {
      expect(p.ugcConfirms, 0, reason: p.id);
      if (p.hasPrice) {
        expect(p.isSeedDemoPrice, isTrue, reason: p.id);
        expect(p.priceBadgeLabel, '未核實', reason: p.id);
        expect(p.trustLabel, contains('未核實'), reason: p.id);
      }
    }
  });

  test('verified park json roundtrip', () {
    const p = Park(
      id: 'ts_causeway',
      name: '時代廣場停車場',
      district: '銅鑼灣',
      lat: 22.2783,
      lng: 114.1827,
      hourlyHkd: 32,
      priceVerificationStatus: PriceVerificationStatus.verified,
      priceVerifiedAt: null,
      priceProvenance: PriceProvenance.gate,
      source: 'seed+osm',
    );
    final again = Park.fromJson(p.toJson());
    expect(again.priceVerificationStatus, PriceVerificationStatus.verified);
    expect(again.priceProvenance, PriceProvenance.gate);
    expect(again.isVerifiedPrice, isTrue);
    expect(again.priceBadgeLabel, '場內核實');
  });

  test('verified sorts before unverified seed at same distance tier', () {
    const verified = Park(
      id: 'a',
      name: 'A',
      district: '銅鑼灣',
      lat: 22.28,
      lng: 114.18,
      hourlyHkd: 30,
      priceVerificationStatus: PriceVerificationStatus.verified,
      priceProvenance: PriceProvenance.gate,
    );
    const seed = Park(
      id: 'b',
      name: 'B',
      district: '銅鑼灣',
      lat: 22.2801,
      lng: 114.1801,
      hourlyHkd: 28,
      source: 'seed',
      priceProvenance: PriceProvenance.seed,
    );
    expect(
      compareParksForDisplay(verified, seed, centerLat: 22.28, centerLng: 114.18),
      lessThan(0),
    );
  });

  test('wedge contains CWB/TST seed ids', () {
    expect(HkWedge.containsPark(hkSeedParks.firstWhere((p) => p.id == 'ts_causeway')), isTrue);
    expect(HkWedge.containsPark(hkSeedParks.firstWhere((p) => p.id == 'hc_tst')), isTrue);
    expect(HkWedge.containsPark(hkSeedParks.firstWhere((p) => p.id == 'ntp_shatin')), isFalse);
  });

  test('splitFeaturedRest collapses unpriced OSM when not searching', () {
    const featured = Park(
      id: 'a',
      name: 'A',
      district: '銅鑼灣',
      lat: 22.28,
      lng: 114.18,
      hourlyHkd: 30,
      source: 'seed',
      priceProvenance: PriceProvenance.seed,
    );
    const osm = Park(
      id: 'osm:1',
      name: '停車場',
      district: '銅鑼灣',
      lat: 22.2805,
      lng: 114.1805,
      source: 'osm',
    );
    final split = splitFeaturedRest([featured, osm], searching: false);
    expect(split.featured, contains(featured));
    expect(split.rest, contains(osm));
  });

  test('search mode keeps flat list', () {
    const a = Park(
      id: 'a',
      name: 'A',
      district: '銅鑼灣',
      lat: 22.28,
      lng: 114.18,
    );
    const b = Park(
      id: 'b',
      name: 'B',
      district: '尖沙咀',
      lat: 22.29,
      lng: 114.17,
    );
    final split = splitFeaturedRest([a, b], searching: true);
    expect(split.featured.length, 2);
    expect(split.rest, isEmpty);
  });
}
