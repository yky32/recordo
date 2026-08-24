import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/hk_seed_parks.dart';
import 'package:recordo/features/session/parking_session.dart';

void main() {
  test('seed parks cover HK with enough samples', () {
    expect(hkSeedParks.length, greaterThanOrEqualTo(40));
    expect(hkSeedParks.any((p) => p.hasPrice), isTrue);
    expect(hkSeedParks.any((p) => !p.hasPrice), isTrue);
    final ids = hkSeedParks.map((e) => e.id).toSet();
    expect(ids.length, hkSeedParks.length);
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
}
