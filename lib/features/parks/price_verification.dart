/// How a displayed price was sourced and whether it was gate-checked.
enum PriceVerificationStatus {
  unverified,
  verified,
  disputed,
}

enum PriceProvenance {
  unknown,
  seed,
  osm,
  ugc,
  gate,
  operator,
}

PriceVerificationStatus parseVerificationStatus(dynamic raw) {
  final s = '$raw'.trim().toLowerCase();
  return switch (s) {
    'verified' => PriceVerificationStatus.verified,
    'disputed' => PriceVerificationStatus.disputed,
    _ => PriceVerificationStatus.unverified,
  };
}

PriceProvenance parsePriceProvenance(dynamic raw) {
  final s = '$raw'.trim().toLowerCase();
  return switch (s) {
    'seed' => PriceProvenance.seed,
    'osm' => PriceProvenance.osm,
    'ugc' => PriceProvenance.ugc,
    'gate' => PriceProvenance.gate,
    'operator' => PriceProvenance.operator,
    _ => PriceProvenance.unknown,
  };
}

String verificationStatusToJson(PriceVerificationStatus s) => switch (s) {
      PriceVerificationStatus.verified => 'verified',
      PriceVerificationStatus.disputed => 'disputed',
      PriceVerificationStatus.unverified => 'unverified',
    };

String priceProvenanceToJson(PriceProvenance p) => switch (p) {
      PriceProvenance.seed => 'seed',
      PriceProvenance.osm => 'osm',
      PriceProvenance.ugc => 'ugc',
      PriceProvenance.gate => 'gate',
      PriceProvenance.operator => 'operator',
      PriceProvenance.unknown => 'unknown',
    };
