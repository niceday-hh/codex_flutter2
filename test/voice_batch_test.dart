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
    await flow.reviewText('明早七点起床，八点出门，晚上九点读书');
    expect(batch?.length, 3); expect(flow.pending, isNull); expect(flow.capturing, isFalse); expect(store.saved, isEmpty);
    flow.dispose(); await tester.pump();
  });
}
