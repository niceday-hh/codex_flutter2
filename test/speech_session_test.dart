import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/asr.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('no pending speech leaves the warm recognition session available', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async => call.method == 'speechJobs' ? '[]' : null);
    final previous = asr.status.value;
    asr.status.value = '离线模型已就绪';
    final session = SpeechSession();
    await session.preparePending();
    expect(asr.status.value, '离线模型已就绪');
    asr.status.value = previous;
    session.status.dispose();
  });
}
