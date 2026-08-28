import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/session/session_cubit.dart';

void main() {
  test('SessionState.alarmFor returns scheduled time for matching session', () {
    final future = DateTime.now().add(const Duration(hours: 1));
    final state = SessionState(
      alarmAt: future,
      alarmSessionId: 's1',
    );
    expect(state.alarmFor('s1'), future);
    expect(state.alarmFor('s2'), isNull);
  });

  test('SessionState.alarmFor ignores expired alarm', () {
    final past = DateTime.now().subtract(const Duration(minutes: 5));
    final state = SessionState(
      alarmAt: past,
      alarmSessionId: 's1',
    );
    expect(state.alarmFor('s1'), isNull);
  });
}
