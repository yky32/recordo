import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/sign_ocr.dart';

void main() {
  test('reads 每小時 next to dollar', () {
    const raw = '時租收費\n星期一至五：\$20/每小時\n星期六日及公眾假期：\$24/每小時';
    expect(SignOcr.parse(raw).hourly, 20);
  });

  test('skips 消費滿 amounts', () {
    const raw = '消費滿 HK\$200 免費泊車 2小時\n時租 \$18/每小時';
    expect(SignOcr.parse(raw).hourly, 18);
  });

  test('HK\$ hourly without 每小時 still in mall range', () {
    expect(SignOcr.parse('時租 HK\$26').hourly, 26);
  });

  test('empty / no number', () {
    expect(SignOcr.parse('停車場入口').hourly, isNull);
  });
}
