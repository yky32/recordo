import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:recordo/features/home/park_clusters.dart';
import 'package:recordo/features/parks/catalog_cache.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/session/parking_session.dart';

void main() {
  test('seed parks cover HK with enough samples', () {
    expect(hkSeedParks.length, greaterThanOrEqualTo(40));
    expect(hkSeedParks.any((p) => p.hasPrice), isTrue);
    expect(hkSeedParks.any((p) => !p.hasPrice), isTrue);
    final ids = hkSeedParks.map((e) => e.id).toSet();
    expect(ids.length, hkSeedParks.length);
  });

  test('prettyParkName localizes OSM type suffixes', () {
    expect(prettyParkName('停車場 (underground)'), '地庫停車場');
    expect(prettyParkName('停車場 (multi-storey)'), '多層停車場');
    expect(prettyParkName('停車場 (rooftop)'), '天台停車場');
    expect(prettyParkName('Times Media Centre'), 'Times Media Centre');
  });

  test('session duration', () {
    final s = ParkingSession(
      id: '1',
      startedAt: DateTime(2026, 1, 1, 12),
      endedAt: DateTime(2026, 1, 1, 13, 30),
      amountHkd: 40,
    );
    expect(s.elapsed.inMinutes, 90);
    expect(s.isActive, isFalse);
  });

  test('catalog dump is skipped when local version is current', () {
    expect(
      catalogNeedsDump(localVersion: 3, remoteVersion: 3, localCount: 100),
      isFalse,
    );
    expect(
      catalogNeedsDump(localVersion: 3, remoteVersion: 4, localCount: 100),
      isTrue,
    );
    expect(
      catalogNeedsDump(localVersion: 0, remoteVersion: 1, localCount: 0),
      isTrue,
    );
  });

  test('park json roundtrip', () {
    const p = Park(
      id: 'osm:way/1',
      name: '測試場',
      district: '中環',
      lat: 22.28,
      lng: 114.16,
      hourlyHkd: 28,
      ugcConfirms: 2,
      source: 'seed+osm',
      priceNote: '首小時 28',
    );
    final again = Park.fromJson(p.toJson());
    expect(again.id, p.id);
    expect(again.name, p.name);
    expect(again.hourlyHkd, 28);
    expect(again.priceNote, '首小時 28');
  });

  test('catalog cache writes a local snapshot', () async {
    final dir = await Directory.systemTemp.createTemp('recordo-cat');
    addTearDown(() => dir.delete(recursive: true));
    final cache = CatalogCache(directory: dir);
    await cache.write(
      CatalogDump(
        version: 7,
        parks: const [
          Park(
            id: 'a',
            name: 'A',
            district: '香港',
            lat: 22.3,
            lng: 114.17,
          ),
        ],
      ),
    );
    final snap = await cache.read();
    expect(snap, isNotNull);
    expect(snap!.version, 7);
    expect(snap.parks.single.id, 'a');
  });

  test('unpriced lots cluster; priced chips stay separate', () {
    Offset toScreen(LatLng ll) =>
        Offset(ll.longitude * 8000, ll.latitude * 8000);
    const priced = Park(
      id: 'p',
      name: '有價',
      district: '灣仔',
      lat: 22.278,
      lng: 114.174,
      hourlyHkd: 28,
    );
    const a = Park(
      id: 'a',
      name: '地庫停車場',
      district: '灣仔',
      lat: 22.27805,
      lng: 114.1741,
    );
    const b = Park(
      id: 'b',
      name: '地庫停車場',
      district: '灣仔',
      lat: 22.27808,
      lng: 114.17412,
    );
    const far = Park(
      id: 'c',
      name: '遠',
      district: '北角',
      lat: 22.29,
      lng: 114.20,
    );
    final clusters = clusterParks(
      parks: const [priced, a, b, far],
      toScreen: toScreen,
      radiusPx: 40,
    );
    expect(clusters.any((c) => c.isSingle && c.primary.id == 'p'), isTrue);
    expect(clusters.any((c) => c.primary.id == 'a' || c.primary.id == 'b'), isFalse);
    expect(clusters.any((c) => c.parks.any((p) => p.id == 'c')), isTrue);
  });

  test('pin price label is compact', () {
    expect(
      pinPriceLabel(
        const Park(
          id: 'x',
          name: 'x',
          district: 'x',
          lat: 0,
          lng: 0,
          hourlyHkd: 28,
        ),
      ),
      '\$28',
    );
  });
}
