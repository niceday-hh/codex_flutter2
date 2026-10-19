import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/asr.dart';
import 'package:timed_memo/reminder.dart';

class WarmAsr extends AsrSession {
  int prepares = 0, releases = 0;
  @override Future<void> prepare() async { prepares++; }
  @override void release() { releases++; super.release(); }
}

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
  testWidgets('an unpinned foreground model expires after 20 seconds', (tester) async {
    final session = WarmAsr();
    await session.retainVoice(); session.releaseVoice();
    expect(session.releases, 0);
    await tester.pump(const Duration(seconds: 19)); expect(session.releases, 0);
    await tester.pump(const Duration(seconds: 1)); expect(session.releases, 1);
    session.release(); session.status.dispose();
  });
  testWidgets('a foreground visit keeps the model warm across idle tab switches', (tester) async {
    final session = WarmAsr()..setForeground(true);
    await session.retainVoice(); session.releaseVoice();
    await tester.pump(const Duration(minutes: 3));
    expect(session.releases, 0);
    session.setForeground(false);
    await tester.pump(const Duration(seconds: 20));
    expect(session.releases, 1);
    session.release(); session.status.dispose();
  });
  testWidgets('memory or TTS release still wins over foreground retention', (tester) async {
    final session = WarmAsr()..setForeground(true);
    await session.retainVoice(); session.releaseVoice();
    await session.withoutModel(() async { expect(session.releases, greaterThan(0)); });
    session.release(); session.status.dispose();
  });
  testWidgets('TTS evicts a warm unpinned model immediately without waiting for idle expiry', (tester) async {
    final session = WarmAsr();
    await session.retainVoice(); session.releaseVoice();
    var generated = false;
    await session.withoutModel(() async { generated = true; expect(session.releases, greaterThan(0)); });
    expect(generated, isTrue);
    session.release(); session.status.dispose();
  });
  testWidgets('tab prewarm and cancelled capture do not queue a model load behind TTS', (tester) async {
    final session = WarmAsr(), finishSpeech = Completer<void>();
    final speech = session.withoutModel(() => finishSpeech.future);
    await tester.pump();
    await session.prewarm(); expect(session.prepares, 0);
    var active = true;
    final lease = session.retainVoice(isCurrent: () => active);
    active = false; finishSpeech.complete();
    await speech; expect(await lease, isFalse); expect(session.prepares, 0);
    session.release(); session.status.dispose();
  });
  test('repeated tab prewarm shares one in-progress preparation', () async {
    final assets = Completer<String>(); var preparations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'prepareAsr') { preparations++; return assets.future; }
      return null;
    });
    final session = AsrSession();
    final first = session.prewarm(); await session.prewarm();
    session.release(); assets.complete('/cancelled-prewarm'); await first;
    expect(preparations, 1); expect(session.status.value, '离线模型已释放');
    session.release(); session.status.dispose();
  });
}
