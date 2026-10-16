import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/voice_parser.dart';
import 'package:timed_memo/reminder.dart';

void main() {
  final end = DateTime(2026, 10, 16, 23, 58, 43, 625);
  test('relative durations preserve the recording end seconds and midnight rollover', () {
    final cases = <String, Duration>{
      '五分钟': const Duration(minutes: 5), '5分钟': const Duration(minutes: 5),
      '半小时': const Duration(minutes: 30), '一个半小时': const Duration(minutes: 90),
      '两小时十五分钟': const Duration(hours: 2, minutes: 15),
      '两天': const Duration(days: 2), '三十秒': const Duration(seconds: 30),
    };
    for (final entry in cases.entries) {
      final parsed = parseVoice('${entry.key}后提醒我喝水', now: end);
      expect(parsed.hasTime, true, reason: entry.key);
      expect(parsed.reminder.date, end.add(entry.value), reason: entry.key);
      expect(parsed.relativeDelay, entry.value);
      expect(parsed.reminder.text, '喝水');
      expect(Reminder.fromJson(parsed.reminder.toJson()).date, parsed.reminder.date);
    }
  });
  test('leading relative instruction after 提醒我 is removed from content', () {
    final p = parseVoice('提醒我五分钟后喝水', now: end);
    expect(p.reminder.date, end.add(const Duration(minutes: 5)));
    expect(p.reminder.text, '喝水');
  });
  test('body dates and recurrence words never modify the instruction', () {
    for (final body in ['整理每天的报表', '看《后天》', '核对每周三的数据']) {
      final p = parseVoice('明天九点提醒我$body', now: end);
      expect(p.reminder.date, DateTime(2026, 10, 17, 9));
      expect(p.reminder.repeat, 'none'); expect(p.reminder.text, body);
    }
    expect(parseVoice('提醒我每天记得喝水', now: end).hasTime, false);
  });
  test('missing, invalid and expired explicit dates do not silently roll forward', () {
    final missing = parseVoice('明天提醒我喝水', now: end);
    expect(missing.reminder.timeConfirmed, false);
    final invalid = parseVoice('2月30日九点提醒我复查', now: end);
    expect(invalid.reminder.dateConfirmed, false); expect(invalid.warning, isNotNull);
    final past = parseVoice('今天九点提醒我开会', now: end);
    expect(past.reminder.date, DateTime(2026, 10, 16, 9)); expect(past.warning, isNotNull);
    final monthPast = parseVoice('10月15号九点提醒我开会', now: end);
    expect(monthPast.reminder.date.year, 2026); expect(monthPast.warning, isNotNull);
    expect(parseVoice('明天25:99提醒我喝水', now: end).reminder.timeConfirmed, false);
    expect(parseVoice('零分钟后提醒我喝水', now: end).reminder.timeConfirmed, false);
  });
  test('legacy records keep zero seconds', () {
    final json = Reminder(date: end).toJson()..remove('second')..remove('millisecond');
    expect(Reminder.fromJson(json).date, DateTime(2026, 10, 16, 23, 58));
  });
}
