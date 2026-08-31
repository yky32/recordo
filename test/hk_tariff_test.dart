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
    expect(t.validations[1].line(), contains('16:00'));
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

  test('Lee Garden days: Mon-Thu vs Fri-Sun+PH', () {
    expect(tariffDaysLabel('mon-thu'), '星期一至四（公眾假期除外）');
    expect(tariffDaysLabel('fri-sun-ph'), '星期五、六、日及公眾假期');
    final t = ParkTariff.tryParse({
      'unitMinutes': 30,
      'bands': [
        {
          'days': 'daily',
          'kind': 'peak',
          'start': '07:00',
          'end': '23:00',
          'amount': 18,
        },
      ],
      'validations': [
        {'days': 'mon-thu', 'spendHkd': 400, 'freeHours': 3},
        {'days': 'fri-sun-ph', 'spendHkd': 600, 'freeHours': 3},
      ],
    });
    expect(t!.validations[0].line(), contains('星期一至四'));
    expect(t.validations[0].line(), contains('400'));
    expect(t.validations[1].line(), contains('星期五、六、日'));
    expect(t.validations[1].line(), contains('600'));
    expect(t.toJson()['validations'][0], isNot(contains('spendHkd')));
    expect(t.toJson()['validations'][0]['spend'], 400);
  });

  test('currency is a field, not baked into keys', () {
    expect(moneyLabel(24, 'HKD'), 'HK\$24');
    expect(moneyLabel(60, 'TWD'), 'NT\$60');
    final tw = ParkTariff.tryParse({
      'unitMinutes': 60,
      'currency': 'TWD',
      'bands': [
        {
          'days': 'daily',
          'kind': 'peak',
          'start': '00:00',
          'end': '24:00',
          'amount': 40,
        },
      ],
      'validations': [
        {'days': 'daily', 'spend': 500, 'freeHours': 2},
      ],
    });
    expect(tw!.currency, 'TWD');
    expect(tw.toJson()['currency'], 'TWD');
    expect(tw.validations.first.line(currency: tw.currency), contains('NT\$500'));
    expect(tw.toJson()['validations'][0].containsKey('spendHkd'), isFalse);
  });

  test('Harcourt House: mon-sat / sun-ph + day package', () {
    final t = ParkTariff.tryParse({
      'unitMinutes': 60,
      'currency': 'HKD',
      'bands': [
        {
          'days': 'mon-sat',
          'kind': 'peak',
          'start': '00:00',
          'end': '24:00',
          'amount': 35,
        },
        {
          'days': 'sun-ph',
          'kind': 'peak',
          'start': '00:00',
          'end': '24:00',
          'amount': 20,
        },
        {
          'days': 'mon-sat',
          'kind': 'day',
          'start': '08:00',
          'end': '18:00',
          'amount': 200,
        },
      ],
    });
    expect(t!.weekdayPeakHourly, 35);
    expect(t.bands.last.isPackage, isTrue);
    expect(t.bands.last.kindLabel, '日泊');
    expect(tariffDaysLabel('mon-sat'), contains('星期一至六'));
    expect(tariffDaysLabel('sun-ph'), contains('星期日'));
  });

  test('20-minute billing maps to hourly chip', () {
    expect(hourlyFromUnitAmount(10, 20), 30);
    expect(hourlyFromUnitAmount(18, 30), 36);
    expect(isValidBillingUnit(20), isTrue);
    expect(isValidBillingUnit(4), isFalse);
    final t = driverTariff(unitMinutes: 20, peak: 10, offpeak: 6);
    expect(t.unitLabel, '20 分鐘');
    expect(t.weekdayPeakHourly, 30);
    expect(ParkTariff.tryParse(t.toJson())!.unitMinutes, 20);
  });

  test('repeat + capHours is 每滿 not five fake thresholds', () {
    final t = ParkTariff.tryParse({
      'unitMinutes': 60,
      'bands': [
        {
          'days': 'daily',
          'kind': 'peak',
          'start': '00:00',
          'end': '24:00',
          'amount': 26,
        },
      ],
      'validations': [
        {
          'days': 'daily',
          'spend': 100,
          'freeHours': 1,
          'repeat': true,
          'capHours': 5,
        },
      ],
    });
    final line = t!.validations.single.line();
    expect(line, contains('每滿'));
    expect(line, contains('100'));
    expect(line, contains('最高 5 小時'));
    expect(t.toJson()['validations'][0]['repeat'], isTrue);
    expect(t.toJson()['validations'][0]['capHours'], 5);
    final again = ParkTariff.tryParse(t.toJson())!;
    expect(again.validations.single.repeat, isTrue);
    expect(again.validations.single.capHours, 5);
  });

  test('park address round-trips and is searchable', () {
    final p = Park.fromJson({
      'id': 'osm:way/1444260592',
      'name': '港威停車場',
      'district': '尖沙咀',
      'lat': 22.297,
      'lng': 114.167,
      'address': '九龍尖沙咀廣東道 3-27 號 海港城',
    });
    expect(p.address, contains('廣東道'));
    expect(Park.fromJson(p.toJson()).address, p.address);
  });
}
