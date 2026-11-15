import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/voice_parser.dart';

void main() {
  final at = DateTime(2030, 1, 1, 10);
  List<ParsedVoice> parse(String s) => parseVoiceBatch(s, now: at, defaults: () => Reminder(speechMode: 'inherit'));
  for (final join in ['，然后', '然后', '，下一条，', '下一条']) {
    for (final numbers in [('五', '十'), ('5', '10'), ('５', '１０')]) {
      test('degree body survives $join $numbers', () {
        final rows = parse('${numbers.$1}分钟后提醒我把火调小一点$join${numbers.$2}分钟后提醒我关火');
        expect(rows.map((p) => p.reminder.text), ['把火调小一点', '关火']);
        expect(rows.map((p) => p.reminder.date), [at.add(const Duration(minutes: 5)), at.add(const Duration(minutes: 10))]);
        expect(rows.every((p) => p.warning == null), isTrue);
      });
    }
  }
  for (final body in ['加一点盐，再加一点水', '把火调小一点', '查看十点的会议资料', '阅读三分钟后再决定是否继续', '阅读下一条通知', '检查第二条合同内容', '阅读“十点开门”', '一点问题都没有']) {
    test('body time or separator mention is protected: $body', () {
      final rows = parse('明天九点提醒我$body');
      expect(rows.length, 1); expect(rows.single.reminder.text, body); expect(rows.single.warning, isNull);
      expect(rows.single.reminder.date, DateTime(2030, 1, 2, 9));
    });
  }
  test('ordinary conjunction stays body; spacing and punctuation survive', () {
    final p = parse('五 分钟后 提醒我 关火，然后检查 A 文件夹').single;
    expect(p.reminder.text, '关火，然后检查 A 文件夹'); expect(p.warning, isNull);
  });
  test('numbered lists and missing schedules remain reviewable', () {
    final rows = parse('第一条五分钟后提醒我关火第二条提醒我买菜第三条十分钟后出门');
    expect(rows.length, 3); expect(rows[1].reminder.text, '买菜'); expect(rows[1].reminder.timeConfirmed, isFalse);
    expect(rows.last.reminder.text, '出门');
    final trailing = parse('五分钟后关火下一条');
    expect(trailing.length, 2); expect(trailing.last.reminder.text, isEmpty); expect(trailing.last.reminder.timeConfirmed, isFalse);
  });
  test('ambiguous body boundary offers lossless alternatives', () {
    final p = parse('明天九点提醒我起床十点学习').single;
    expect(p.reminder.text, '起床十点学习'); expect(p.issue, VoiceIssue.boundary);
    expect(p.evidence, '十点学习');
    expect(p.alternatives.map((p) => p.reminder.text), ['起床', '学习']);
    expect(p.alternatives.map((p) => p.reminder.date), [DateTime(2030, 1, 2, 9), DateTime(2030, 1, 2, 10)]);
  });
  test('relative reference offers both clocks and dependencies block scheduling', () {
    final rows = parse('五分钟后提醒我调小火，再过十分钟提醒我关火');
    expect(rows.length, 2); expect(rows.last.issue, VoiceIssue.relativeReference);
    expect(rows.last.relativeDelay, const Duration(minutes: 10)); expect(rows.last.reference, at);
    expect(rows.last.previousTime, at.add(const Duration(minutes: 5)));
    final dependent = parse('第一条完成后十分钟提醒我关火').single;
    expect(dependent.issue, VoiceIssue.dependency); expect(dependent.reminder.timeConfirmed, isFalse);
  });
  test('explicit separator with no schedule keeps the missing-time body', () {
    final rows = parse('五分钟后关火，然后下一条，买菜');
    expect(rows.map((p) => p.reminder.text), ['关火', '买菜']);
    expect(rows.last.reminder.timeConfirmed, isFalse);
  });
  test('relative wording with optional after keeps a clean body', () {
    final rows = parse('五分钟后提醒我调小火，再过十分钟后提醒我关火');
    expect(rows.last.reminder.text, '关火'); expect(rows.last.relativeDelay, const Duration(minutes: 10));
    expect(rows.last.issue, VoiceIssue.relativeReference);
  });
  test('row settings do not leak and legacy single parser remains untouched', () {
    final rows = parse('五分钟后提醒我喝水，开启语音播报，总共提醒五次，下一条十分钟后提醒我关火');
    expect(rows.length, 2); expect(rows.first.reminder.speechMode, 'on'); expect(rows.first.reminder.totalCount, 5);
    expect(rows.last.reminder.speechMode, 'inherit'); expect(rows.last.reminder.totalCount, 3);
    final single = parseVoice('五分钟后提醒我把火调小一点然后十分钟后提醒我关火', now: at);
    expect(single.reminder.text, '把火调小一点然后十分钟后提醒我关火');
  });
  test('limit retains every word rather than dropping tail', () {
    final raw = List.generate(11, (i) => '下一条五分钟后事项$i').join();
    final rows = parse(raw); expect(rows.single.issue, VoiceIssue.limit); expect(rows.single.reminder.text, raw);
  });
}
