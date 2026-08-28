import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/community_paid_session.dart';

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
}
