import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/asr.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/voice_flow.dart';

class FakeCapture implements VoiceCapture {
  final results = <CapturedVoice>[];
  final silences = <double>[];
  final waitsForModel = <bool>[];
  int opens = 0, releases = 0, cancels = 0;
  Completer<CapturedVoice>? delayed;
  @override Future<void> open({bool waitForModel = true}) async { opens++; waitsForModel.add(waitForModel); }
  @override Future<void> start(double silence, void Function(int) endpoint, void Function(Object) level) async { silences.add(silence); }
  @override Future<CapturedVoice> stop({int? endSample}) async => delayed == null ? results.removeAt(0) : delayed!.future;
  @override Future<void> cancel() async { cancels++; }
  @override void release() { releases++; }
}
class FakeStore extends MemoStore {
  final saved = <Reminder>[];
  @override Future<void> save(Reminder r) async { saved.add(r); }
}
class ReadyAsr extends AsrSession {
  @override Future<void> prepare() async {}
}

void main() {
  final at = DateTime(2030, 1, 1, 10);
  testWidgets('offline command, body, confirmation save one task without TTS', (tester) async {
    final c = FakeCapture(), store = FakeStore();
    var opened = 0;
    final flow = VoiceFlow(capture: c, store: store, clock: () => at,
      openVoicePage: () => opened++, onSaved: () async {});
    await flow.startCommands();
    expect(c.waitsForModel, [true]);
    expect(flow.phase, VoicePhase.commands);
    expect(c.silences, [0.7]);
    c.results.add(CapturedVoice('开始录音', at));
    await flow.finish();
    expect(opened, 1); expect(flow.phase, VoicePhase.recording); expect(c.silences.last, 5);
    c.results.add(CapturedVoice('二十分钟后提醒我做饭，开启语音提醒', at));
    await flow.finish(endSample: 16000);
    expect(flow.pending?.reminder.text, '做饭');
    expect(flow.pending?.reminder.date, at.add(const Duration(minutes: 20)));
    expect(flow.pending?.reminder.speechMode, 'on');
    expect(flow.phase, VoicePhase.confirming); expect(store.saved, isEmpty);
    c.results.add(CapturedVoice('确认订单', at));
    await flow.finish();
    expect(store.saved, isEmpty); expect(flow.pending, isNotNull);
    c.results.add(CapturedVoice('确认', at));
    await flow.finish();
    await flow.confirm();
    expect(store.saved.length, 1); expect(flow.pending, isNull);
    expect(flow.text, isEmpty); expect(flow.reference, isNull);
    flow.dispose(); await tester.pump();
  });
  testWidgets('a start command may contain its memo in the same utterance', (tester) async {
    final c = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: c, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {});
    await flow.startCommands();
    c.results.add(CapturedVoice('打开录音，五分钟后提醒我喝水', at));
    await flow.finish();
    expect(flow.pending?.reminder.text, '喝水'); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
  testWidgets('re-record discards the draft and cancel never creates a reminder', (tester) async {
    final c = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: c, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {});
    await flow.reviewText('五分钟后提醒我确认订单');
    c.results.add(CapturedVoice('重新录音', at)); await flow.finish();
    expect(flow.phase, VoicePhase.recording); expect(flow.pending, isNull);
    c.results.add(CapturedVoice('五分钟后提醒我买牛奶', at)); await flow.finish();
    c.results.add(CapturedVoice('取消', at)); await flow.finish();
    expect(flow.pending, isNull); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
  testWidgets('missing or expired time blocks voice and button confirmation', (tester) async {
    final c = FakeCapture(), store = FakeStore();
    var clock = at;
    final flow = VoiceFlow(capture: c, store: store, clock: () => clock, openVoicePage: () {}, onSaved: () async {});
    await flow.reviewText('明天提醒我买牛奶');
    await flow.confirm(); expect(store.saved, isEmpty); expect(flow.validationError, isNotNull);
    await flow.reviewText('五分钟后提醒我喝水');
    clock = at.add(const Duration(minutes: 6));
    await flow.confirm(); expect(store.saved, isEmpty); expect(flow.pending, isNotNull);
    flow.dispose(); await tester.pump();
  });
  testWidgets('late transcription after background cancellation cannot open or save a draft', (tester) async {
    final c = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: c, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {});
    await flow.startRecording();
    expect(c.waitsForModel, [false]);
    c.delayed = Completer<CapturedVoice>();
    final recognizing = flow.finish();
    await tester.pump();
    final stopped = flow.cancel();
    c.delayed!.complete(CapturedVoice('五分钟后提醒我喝水', at));
    await recognizing; await stopped;
    expect(flow.phase, VoicePhase.idle); expect(flow.pending, isNull); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
  testWidgets('timeouts close pre-listening and keep an unconfirmed draft without saving', (tester) async {
    final c = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: c, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {});
    await flow.startCommands();
    await tester.pump(const Duration(seconds: 15)); await tester.pump();
    expect(flow.phase, VoicePhase.idle); expect(store.saved, isEmpty);
    await flow.reviewText('五分钟后提醒我喝水');
    await tester.pump(const Duration(seconds: 20)); await tester.pump();
    expect(flow.phase, VoicePhase.idle); expect(flow.pending, isNotNull); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
  testWidgets('unknown commands keep only the remaining listening window', (tester) async {
    var clock = at;
    final c = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: c, store: store, clock: () => clock, openVoicePage: () {}, onSaved: () async {});
    await flow.startCommands();
    clock = at.add(const Duration(seconds: 10));
    c.results.add(CapturedVoice('今天天气不错', clock)); await flow.finish();
    expect(flow.phase, VoicePhase.commands); expect(flow.secondsLeft, 5);
    await tester.pump(const Duration(seconds: 5)); await tester.pump();
    expect(flow.phase, VoicePhase.idle);
    await flow.reviewText('五分钟后提醒我喝水');
    clock = clock.add(const Duration(seconds: 21));
    c.results.add(CapturedVoice('没有听清', clock)); await flow.finish();
    expect(flow.phase, VoicePhase.idle); expect(flow.pending, isNotNull); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
  testWidgets('interactive recognition holds postpone TTS until the session releases', (tester) async {
    final session = ReadyAsr();
    await session.retainVoice();
    var generated = false;
    final tts = session.withoutModel(() async { generated = true; });
    await tester.pump(); expect(generated, isFalse);
    session.releaseVoice(); await tts;
    expect(generated, isTrue);
    session.release(); session.status.dispose();
  });
  test('confirmation matches complete commands only', () {
    expect(isVoiceConfirm('确认。'), isTrue);
    for (final text in ['不确认', '确认订单', '请提醒我确认', '取消确认']) { expect(isVoiceConfirm(text), isFalse); }
  });
}
