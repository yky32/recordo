import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/core/location/user_location.dart';

void main() {
  test('UserLocationResult.ok when lat/lng present', () {
    const r = UserLocationResult(lat: 22.28, lng: 114.17);
    expect(r.ok, isTrue);
    expect(r.error, isNull);
  });

  test('UserLocationResult.not ok when error set', () {
    const r = UserLocationResult(error: '未有定位權限');
    expect(r.ok, isFalse);
  });
}
