import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/contribution_copy.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/sync_outbox.dart';

void main() {
  test('paid outbox job is not poison when payload valid', () {
    final job = SyncJob(
      id: 'paid-1',
      type: 'paid',
      payload: const {
        'parkId': 'seed:cwb-1',
        'amountHkd': 45,
        'durationMinutes': 90,
      },
      createdAt: DateTime.utc(2026, 8, 28),
    );
    expect(outboxJobPoison(job), isFalse);
  });

  test('paid outbox job is poison without park id', () {
    final job = SyncJob(
      id: 'paid-bad',
      type: 'paid',
      payload: const {'amountHkd': 45, 'durationMinutes': 90},
      createdAt: DateTime.utc(2026, 8, 28),
    );
    expect(outboxJobPoison(job), isTrue);
  });

  test('contribution copy mentions reporter count', () {
    final park = Park(
      id: 'x',
      name: 'Test',
      district: '銅鑼灣',
      lat: 22.28,
      lng: 114.18,
      ugcConfirms: 3,
    );
    expect(
      ContributionCopy.priceReport(cloud: true, park: park),
      '已分享 · 呢個場而家 3 人報過',
    );
    expect(
      ContributionCopy.paidSession(cloud: true),
      '已分享實付 · 多謝',
    );
  });
}
