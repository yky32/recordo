import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/contribution_copy.dart';

void main() {
  test('paidSession copy distinguishes cloud vs pending', () {
    expect(ContributionCopy.paidSession(cloud: true), contains('已分享實付'));
    expect(ContributionCopy.paidSession(cloud: false), contains('本機'));
    expect(
      ContributionCopy.paidSessionOfflineBuild,
      contains('未接雲端'),
    );
  });
}
