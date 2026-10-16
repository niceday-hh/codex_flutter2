import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/asr.dart';
import 'package:timed_memo/reminder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('leaving during asset preparation skips native model loading', () async {
    final assets = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'prepareAsr') return assets.future;
      return null;
    });
    final session = AsrSession();
    final ready = session.prepare();
    session.release();
    assets.complete('/model-loading-must-not-start');
    await ready;
    expect(session.status.value, '离线模型已释放');
    session.release(); session.status.dispose();
  });
}
