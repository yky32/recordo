import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/community_paid_session.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';

void main() {
  test('CommunityPaidSession parses Supabase row', () {
    final row = CommunityPaidSession.fromJson({
      'amount_hkd': 65,
      'duration_minutes': 120,
      'created_at': '2026-08-28T03:00:00Z',
    });
    expect(row.amountHkd, 65);
    expect(row.durationMinutes, 120);
    expect(row.duration.inHours, 2);
  });

  test('ParkCatalogState exposes community paid by park id', () {
    final session = CommunityPaidSession(
      amountHkd: 40,
      durationMinutes: 60,
      createdAt: DateTime.utc(2026, 8, 28),
    );
    final state = ParkCatalogState(
      communityPaidByPark: {'seed:cwb-1': [session]},
      communityPaidLoading: {'seed:cwb-2'},
    );
    expect(state.communityPaidFor('seed:cwb-1'), [session]);
    expect(state.communityPaidFor('missing'), isEmpty);
    expect(state.communityPaidLoadingFor('seed:cwb-2'), isTrue);
    expect(state.communityPaidLoadingFor('seed:cwb-1'), isFalse);
  });
}
