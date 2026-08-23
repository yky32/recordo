class ParkingSession {
  const ParkingSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.parkId,
    this.parkName,
    this.amountHkd,
    this.note = '',
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? parkId;
  final String? parkName;
  final double? amountHkd;
  final String note;

  bool get isActive => endedAt == null;

  Duration get elapsed {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'parkId': parkId,
        'parkName': parkName,
        'amountHkd': amountHkd,
        'note': note,
      };

  factory ParkingSession.fromJson(Map<String, dynamic> j) {
    return ParkingSession(
      id: j['id'] as String,
      startedAt: DateTime.parse(j['startedAt'] as String),
      endedAt: j['endedAt'] != null
          ? DateTime.parse(j['endedAt'] as String)
          : null,
      parkId: j['parkId'] as String?,
      parkName: j['parkName'] as String?,
      amountHkd: (j['amountHkd'] as num?)?.toDouble(),
      note: j['note'] as String? ?? '',
    );
  }

  ParkingSession copyWith({
    DateTime? endedAt,
    String? parkId,
    String? parkName,
    double? amountHkd,
    String? note,
  }) {
    return ParkingSession(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      parkId: parkId ?? this.parkId,
      parkName: parkName ?? this.parkName,
      amountHkd: amountHkd ?? this.amountHkd,
      note: note ?? this.note,
    );
  }
}
