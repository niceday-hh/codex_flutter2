import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/voice_parser.dart';

void main() {
  final now = DateTime(2026, 10, 14, 8); // Wednesday.
  test('weekly Chinese voice retains time, weekday and content', () {
    final p = parseVoice('每周三上午九点，提醒我参加项目例会', now: now);
    expect(p.hasTime, isTrue);
    expect(p.reminder.date, DateTime(2026, 10, 14, 9));
    expect(p.reminder.repeat, 'weekly'); expect(p.reminder.days, [3]);
    expect(p.reminder.text, '参加项目例会');
  });
  test('tomorrow afternoon, half hour and one-off', () {
    final p = parseVoice('明天下午三点半提醒我领取快递', now: now);
    expect(p.reminder.date, DateTime(2026, 10, 15, 15, 30));
    expect(p.reminder.repeat, 'none'); expect(p.reminder.text, '领取快递');
  });
  test('daily and workdays', () {
    expect(parseVoice('每天晚上九点提醒我喝水', now: now).reminder.date.hour, 21);
    expect(parseVoice('工作日早上八点提醒我出门', now: now).reminder.days, [1, 2, 3, 4, 5]);
  });
  test('explicit month/day and colon time', () {
    final p = parseVoice('10月20号09:15提醒我复查', now: now);
    expect(p.reminder.date, DateTime(2026, 10, 20, 9, 15));
  });
  test('missing and invalid time require confirmation', () {
    expect(parseVoice('提醒我买牛奶', now: now).hasTime, isFalse);
    expect(parseVoice('明天二十五点提醒我买牛奶', now: now).hasTime, isFalse);
  });
  test('past weekday rolls to next week', () {
    final p = parseVoice('周三早上七点提醒我开会', now: now);
    expect(p.reminder.date, DateTime(2026, 10, 21, 7));
    expect(p.reminder.repeat, 'none');
  });
}
