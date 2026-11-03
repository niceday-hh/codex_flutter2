import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/asr.dart';
import 'package:timed_memo/reminder.dart';

class WarmAsr extends AsrSession {
  WarmAsr({super.clock});
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
  testWidgets('an unpinned background model expires after the default 30 seconds', (tester) async {
    final session = WarmAsr(clock: tester.binding.clock.now);
    await session.retainVoice(); session.releaseVoice();
    expect(session.releases, 0);
    await tester.pump(const Duration(seconds: 29)); expect(session.releases, 0);
    await tester.pump(const Duration(seconds: 1)); expect(session.releases, 1);
    session.release(); session.status.dispose();
  });
  testWidgets('a foreground visit keeps the model warm across idle tab switches', (tester) async {
    final session = WarmAsr(clock: tester.binding.clock.now)..setForeground(true);
    await session.retainVoice(); session.releaseVoice();
    await tester.pump(const Duration(minutes: 3));
    expect(session.releases, 0);
    session.setForeground(false);
    await tester.pump(const Duration(seconds: 30));
    expect(session.releases, 1);
    session.release(); session.status.dispose();
  });
  for (final seconds in asrBackgroundRetentionOptions) {
    testWidgets('background retention honors $seconds seconds and releases after capture stops', (tester) async {
      final session = WarmAsr(clock: tester.binding.clock.now)
        ..setForeground(true)..setBackgroundRetentionSeconds(seconds);
      await session.retainVoice();
      session.setForeground(false);
      session.releaseVoice();
      if (seconds > 0) {
        await tester.pump(Duration(seconds: seconds - 1));
        expect(session.releases, 0);
        await tester.pump(const Duration(seconds: 1));
      }
      expect(session.releases, greaterThan(0));
      session.release(); session.status.dispose();
    });
  }
  testWidgets('returning to the foreground cancels expiry and starts a fresh background window', (tester) async {
    final session = WarmAsr(clock: tester.binding.clock.now)
      ..setForeground(true)..setBackgroundRetentionSeconds(15);
    await session.retainVoice(); session.releaseVoice();
    session.setForeground(false);
    await tester.pump(const Duration(seconds: 14));
    session.setForeground(true);
    await tester.pump(const Duration(minutes: 2));
    expect(session.releases, 0);
    session.setForeground(false);
    await tester.pump(const Duration(seconds: 14)); expect(session.releases, 0);
    await tester.pump(const Duration(seconds: 1)); expect(session.releases, 1);
    session.release(); session.status.dispose();
  });
  testWidgets('a slow capture shutdown and repeated paused events do not extend retention', (tester) async {
    final session = WarmAsr(clock: tester.binding.clock.now)
      ..setForeground(true)..setBackgroundRetentionSeconds(15);
    await session.retainVoice(); session.setForeground(false);
    await tester.pump(const Duration(seconds: 10));
    session.setForeground(false); session.releaseVoice();
    await tester.pump(const Duration(seconds: 4)); expect(session.releases, 0);
    await tester.pump(const Duration(seconds: 1)); expect(session.releases, 1);
    session.release(); session.status.dispose();
  });
  testWidgets('resuming after process suspension checks the deadline before a delayed timer fires', (tester) async {
    var now = DateTime(2026, 11, 3);
    final session = WarmAsr(clock: () => now)..setForeground(true)..setBackgroundRetentionSeconds(15);
    await session.retainVoice(); session.releaseVoice(); session.setForeground(false);
    now = now.add(const Duration(seconds: 16));
    session.setForeground(true);
    expect(session.releases, 1);
    await tester.pump(const Duration(seconds: 60)); expect(session.releases, 1);
    session.release(); session.status.dispose();
  });
  testWidgets('background expiry defers destruction until an active voice lease drains', (tester) async {
    final session = WarmAsr(clock: tester.binding.clock.now)..setForeground(true);
    await session.retainVoice(); session.setForeground(false);
    await tester.pump(const Duration(seconds: 30));
    expect(session.releases, 1);
    expect(session.status.value, isNot(contains('已释放')));
    session.releaseVoice();
    expect(session.status.value, contains('已释放'));
    session.release(); session.status.dispose();
  });
  testWidgets('memory pressure and TTS can evict during a background grace period', (tester) async {
    for (final tts in [false, true]) {
      final session = WarmAsr(clock: tester.binding.clock.now)
        ..setForeground(true)..setBackgroundRetentionSeconds(60);
      await session.retainVoice(); session.releaseVoice(); session.setForeground(false);
      if (tts) { await session.withoutModel(() async {}); } else { session.release(); }
      expect(session.status.value, contains('已释放'));
      final released = session.releases;
      await tester.pump(const Duration(seconds: 60)); expect(session.releases, released);
      session.release(); session.status.dispose();
    }
  });
  test('retention values have a bounded migration default', () {
    for (final value in [null, -1, 20, 120, 30.0, '30']) {
      expect(asrBackgroundRetentionSeconds(value), 30);
    }
    expect(asrBackgroundRetentionLabel(0), '立即释放');
    expect(asrBackgroundRetentionLabel(15), '15 秒');
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
