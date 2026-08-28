import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_tariff.dart';
import 'package:recordo/features/parks/price_verification.dart';

void main() {
  test('Times Square tariff: 30 min peak maps to 36/hr chip', () {
    final t = ParkTariff.tryParse(timesSquareTariffJson());
    expect(t, isNotNull);
    expect(t!.unitMinutes, 30);
    expect(t.weekdayPeakHourly, 36);
    expect(t.weekdayOffpeakHourly, 16);
    expect(t.bands, hasLength(4));
    expect(t.validations, hasLength(3));
    expect(t.validations[1].line, contains('16:00'));
  });

  test('operator verified park shows 官方牌價 not 司機報價', () {
    final p = Park(
      id: 'osm:node/2987721138',
      name: '時代廣場停車場',
      district: '銅鑼灣',
      lat: 22.2783,
      lng: 114.1827,
      hourlyHkd: 36,
      nightHkd: 16,
      priceVerificationStatus: PriceVerificationStatus.verified,
      priceProvenance: PriceProvenance.operator,
      tariff: ParkTariff.tryParse(timesSquareTariffJson()),
    );
    expect(p.priceBadgeLabel, '官方牌價');
    expect(p.priceSummary, contains('官方牌價'));
    expect(p.trustLabel, contains('半小時'));
    final again = Park.fromJson(p.toJson());
    expect(again.tariff!.weekdayPeakHourly, 36);
    expect(again.priceBadgeLabel, '官方牌價');
  });
}
