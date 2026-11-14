import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/scene_templates.dart';
import 'package:timed_memo/voice_flow.dart';
import 'package:timed_memo/voice_parser.dart';
import 'voice_flow_test.dart' show FakeCapture, FakeStore;

void main() {
  final at = DateTime(2030, 1, 1, 10);
  List<ParsedVoice> parse(String s) => parseVoiceBatch(s, now: at, defaults: () => Reminder(speechMode: 'inherit'));
  test('multiple explicit tasks inherit a spoken day, not the first clock period', () {
    final rows = parse('明早七点起床，八点出门，晚上九点读书');
    expect(rows.map((p) => p.reminder.text), ['起床', '出门', '读书']);
    expect(rows.map((p) => p.reminder.date), [DateTime(2030, 1, 2, 7), DateTime(2030, 1, 2, 8), DateTime(2030, 1, 2, 21)]);
    expect(rows.every((p) => p.warning == null), isTrue);
    expect(identical(rows[0].reminder, rows[1].reminder), isFalse);
  });
  test('body commas and suffix controls stay attached to the correct reminder', () {
    final rows = parse('明天八点提醒我买牛奶，面包和水果，开启语音播报；下午三点提醒我开会');
    expect(rows.length, 2);
    expect(rows.first.reminder.text, '买牛奶，面包和水果');
    expect(rows.first.reminder.speechMode, 'on');
    expect(rows.last.reminder.speechMode, 'inherit');
    expect(rows.last.reminder.date, DateTime(2030, 1, 2, 15));
  });
  test('single task and quoted schedules are not split', () {
    expect(parse('五分钟后提醒我喝水，休息一下眼睛').length, 1);
    expect(parse('明天八点提醒我阅读“九点开门，十点关门”').length, 1);
  });
  test('explicit day resets inheritance and relative durations use capture time', () {
    final rows = parse('明天八点出门，后天九点开会，十分钟后喝水');
    expect(rows.length, 3);
    expect(rows[1].reminder.date, DateTime(2030, 1, 3, 9));
    expect(rows[2].reminder.date, at.add(const Duration(minutes: 10)));
  });
  for (final input in ['明天九点起床十点学习', '明天9点起床10点学习', '明天 九点 起床 十点 学习',
    '提醒我明天九点起床然后十点学习', '明天九点起床、十点学习', '明天09:00起床10:00学习']) {
    test('unpunctuated ASR candidates: $input', () {
      final rows = parse(input);
      expect(rows.map((p) => p.reminder.text), ['起床', '学习']);
      expect(rows.map((p) => p.reminder.date), [DateTime(2030, 1, 2, 9), DateTime(2030, 1, 2, 10)]);
      expect(rows.every((p) => p.warning == null), isTrue);
    });
  }
  test('quoted times stay in the body while a following real task is split', () {
    final rows = parse('明天九点阅读“十点开门”十一点出门');
    expect(rows.map((p) => p.reminder.text), ['阅读“十点开门”', '出门']);
    expect(rows.last.reminder.date, DateTime(2030, 1, 2, 11));
    expect(parse('明天九点阅读“十点开门').length, 1);
  });
  test('short day aliases do not rewrite words in the reminder body', () {
    final rows = parse('明早九点整理今晚的资料十点学习');
    expect(rows.map((p) => p.reminder.text), ['整理今晚的资料', '学习']);
    expect(rows.last.reminder.date, DateTime(2030, 1, 2, 10));
  });
  test('missing bodies and excessive candidates stay reviewable and cannot be silently dropped', () {
    final rows = parse('明天九点，十点学习');
    expect(rows.length, 2); expect(rows.first.reminder.text, isEmpty);
    final excessive = parse(List.generate(11, (i) => '明天九点任务$i').join('，'));
    expect(excessive.single.warning, contains('最多核对10条'));
  });
  test('templates create independent drafts and do not save tasks', () {
    final store = MemoStore();
    final first = builtInScenes.first.instantiate(at, store);
    final second = builtInScenes.first.instantiate(at.add(const Duration(days: 1)), store);
    expect(first.map((p) => p.reminder.text), ['阅读', '休息一下', '复习与整理']);
    expect(first.last.reminder.date, at.add(const Duration(minutes: 40)));
    first.first.reminder.text = '修改';
    expect(second.first.reminder.text, '阅读');
    expect(store.reminders, isEmpty);
  });
  testWidgets('hands-free opens before model and manual takeover replaces session', (tester) async {
    final capture = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: capture, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {});
    await flow.startCommands();
    expect(capture.waitsForModel, [false]);
    await flow.startRecording();
    expect(flow.phase, VoicePhase.recording);
    expect(capture.waitsForModel, [false, false]);
    flow.dispose(); await tester.pump();
  });
  testWidgets('cancel and restart do not queue behind a late transcription', (tester) async {
    final capture = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: capture, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {});
    await flow.startRecording();
    final late = capture.delayed = Completer<CapturedVoice>();
    final finishing = flow.finish(); await tester.pump();
    await flow.cancel(); await flow.startRecording();
    expect(flow.phase, VoicePhase.recording);
    late.complete(CapturedVoice('五分钟后提醒我喝水', at)); await finishing;
    expect(flow.pending, isNull); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
  testWidgets('multiple tasks open review without writing any reminder', (tester) async {
    final capture = FakeCapture(), store = FakeStore();
    List<ParsedVoice>? batch;
    final flow = VoiceFlow(capture: capture, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {},
      onBatch: (_, rows) async { batch = rows; });
    flow.selectTaskMode(VoiceTaskMode.multiple);
    await flow.reviewText('明早七点起床，八点出门，晚上九点读书');
    expect(batch?.length, 3); expect(flow.pending, isNull); expect(flow.capturing, isFalse); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
  testWidgets('default single-task mode never dispatches a batch', (tester) async {
    final capture = FakeCapture(), store = FakeStore();
    var batches = 0;
    final flow = VoiceFlow(capture: capture, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {},
      onBatch: (_, rows) async { batches++; });
    await flow.reviewText('明天九点起床，十点学习');
    expect(flow.taskMode, VoiceTaskMode.single); expect(batches, 0); expect(flow.pending, isNotNull);
    flow.dispose(); await tester.pump();
  });
  testWidgets('home command accepts mode and all tasks in one unpunctuated utterance', (tester) async {
    final capture = FakeCapture(), store = FakeStore();
    List<ParsedVoice>? batch; String? source;
    final flow = VoiceFlow(capture: capture, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {},
      onBatch: (text, rows) async { source = text; batch = rows; });
    await flow.startCommands();
    capture.results.add(CapturedVoice('开始录音多任务模式明天九点起床十点学习', at));
    await flow.finish();
    expect(flow.taskMode, VoiceTaskMode.multiple); expect(batch?.length, 2);
    expect(source, '明天九点起床十点学习'); expect(store.saved, isEmpty); expect(flow.pending, isNull);
    expect(batch!.last.reminder.date, DateTime(2030, 1, 2, 10));
    flow.dispose(); await tester.pump();
  });
  testWidgets('each home entry defaults to single and explicit single overrides previous selection', (tester) async {
    final capture = FakeCapture(), store = FakeStore(); var batches = 0;
    final flow = VoiceFlow(capture: capture, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {},
      onBatch: (_, rows) async { batches++; });
    flow.selectTaskMode(VoiceTaskMode.multiple);
    await flow.startCommands(); expect(flow.taskMode, VoiceTaskMode.single);
    capture.results.add(CapturedVoice('开始录音明天九点起床十点学习', at)); await flow.finish();
    expect(batches, 0); expect(flow.pending, isNotNull);
    await flow.cancel(); flow.selectTaskMode(VoiceTaskMode.multiple);
    await flow.reviewText('单任务模式明天九点起床十点学习');
    expect(flow.taskMode, VoiceTaskMode.single); expect(batches, 0);
    flow.dispose(); await tester.pump();
  });
  testWidgets('multiple mode with only one candidate still opens explicit review', (tester) async {
    final capture = FakeCapture(), store = FakeStore(); List<ParsedVoice>? batch;
    final flow = VoiceFlow(capture: capture, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {},
      onBatch: (_, rows) async { batch = rows; });
    flow.selectTaskMode(VoiceTaskMode.multiple);
    await flow.startRecording(); flow.selectTaskMode(VoiceTaskMode.single);
    expect(flow.taskMode, VoiceTaskMode.multiple); // Mode is locked during capture.
    capture.results.add(CapturedVoice('明天九点起床', at)); await flow.finish();
    expect(batch?.length, 1); expect(flow.pending, isNull); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
  testWidgets('mode-only prefix keeps recording and body mentions never change mode', (tester) async {
    final capture = FakeCapture(), store = FakeStore(); List<ParsedVoice>? batch;
    final flow = VoiceFlow(capture: capture, store: store, clock: () => at, openVoicePage: () {}, onSaved: () async {},
      onBatch: (_, rows) async { batch = rows; });
    await flow.startCommands();
    capture.results.add(CapturedVoice('开始录音，多任务模式', at)); await flow.finish();
    expect(flow.phase, VoicePhase.recording); expect(flow.taskMode, VoiceTaskMode.multiple);
    capture.results.add(CapturedVoice('明天九点起床十点学习', at)); await flow.finish(); expect(batch?.length, 2);
    await flow.cancel(); flow.selectTaskMode(VoiceTaskMode.single);
    await flow.reviewText('明天九点提醒我研究多任务模式');
    expect(flow.taskMode, VoiceTaskMode.single); expect(flow.pending?.reminder.text, '研究多任务模式');
    await flow.cancel(); await flow.reviewText('多任务管理教程');
    expect(flow.taskMode, VoiceTaskMode.single); expect(flow.text, '多任务管理教程');
    flow.dispose(); await tester.pump();
  });

}
