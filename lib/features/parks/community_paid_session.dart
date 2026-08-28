/// A driver-reported real payment from Supabase `paid_sessions`.
class CommunityPaidSession {
  const CommunityPaidSession({
    required this.amountHkd,
    required this.durationMinutes,
    required this.createdAt,
  });

  final double amountHkd;
  final int durationMinutes;
  final DateTime createdAt;

  Duration get duration => Duration(minutes: durationMinutes);

  factory CommunityPaidSession.fromJson(Map<String, dynamic> m) {
    return CommunityPaidSession(
      amountHkd: (m['amount_hkd'] as num).toDouble(),
      durationMinutes: m['duration_minutes'] as int? ?? 0,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}
