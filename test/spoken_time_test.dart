import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/spoken_time.dart';

void main() {
  // 2026-11-02 is a Monday; 20:04 is late enough that “九点” has to roll over.
  final now = DateTime(2026, 11, 2, 20, 4);

  SpokenTime? at(String text, {DateTime? from, DateTime? preferDate}) =>
      parseSpokenTime(text, now: now, from: from, preferDate: preferDate);

  group('durations', () {
    test('minutes later', () {
      final t = at('30 分钟后')!;
      expect(t.at, DateTime(2026, 11, 2, 20, 34));
      expect(t.relative, isTrue);
    });

    test('an hour and a half', () {
      expect(at('一个半小时以后')!.at, DateTime(2026, 11, 2, 21, 34));
    });

    test('half an hour', () {
      expect(at('晚半小时')!.at, DateTime(2026, 11, 2, 20, 34));
    });

    test('stacks on the selected time, not on now', () {
      final selected = DateTime(2026, 11, 3, 9);
      expect(at('再晚 20 分钟', from: selected)!.at, DateTime(2026, 11, 3, 9, 20));
    });

    test('ignores a selected time in the past', () {
      final past = DateTime(2026, 11, 1, 9);
      expect(at('20 分钟后', from: past)!.at, DateTime(2026, 11, 2, 20, 24));
    });
  });

  group('clock and calendar', () {
    test('tomorrow afternoon', () {
      expect(at('明天下午三点')!.at, DateTime(2026, 11, 3, 15));
    });

    test('day after tomorrow, half past eight', () {
      expect(at('后天早上八点半')!.at, DateTime(2026, 11, 4, 8, 30));
    });

    test('next Wednesday keeps the clock', () {
      expect(at('周三上午十点')!.at, DateTime(2026, 11, 4, 10));
    });

    test('a weekday earlier in the week means next week', () {
      expect(at('周日晚上八点')!.at, DateTime(2026, 11, 8, 20));
    });

    test('explicit month and day', () {
      expect(at('11 月 5 日 9 点')!.at, DateTime(2026, 11, 5, 9));
    });

    test('bare clock that already passed rolls to tomorrow', () {
      expect(at('21:40')!.at, DateTime(2026, 11, 2, 21, 40));
      expect(at('9 点')!.at, DateTime(2026, 11, 3, 9));
    });

    test('keeps the date already selected', () {
      final prefer = DateTime(2026, 11, 7, 8);
      expect(at('下午四点', preferDate: prefer)!.at, DateTime(2026, 11, 7, 16));
    });

    test('strips the polite verbs', () {
      expect(at('帮我把提醒改到明天下午三点')!.at, DateTime(2026, 11, 3, 15));
      // 20:04 is already past eight, so this is tomorrow evening.
      expect(at('推迟到晚上八点')!.at, DateTime(2026, 11, 3, 20));
    });
  });

  group('edge cases', () {
    test('midnight variants', () {
      expect(at('晚上十二点')!.at, DateTime(2026, 11, 2, 0).add(const Duration(days: 1)));
      expect(at('中午十二点')!.at, DateTime(2026, 11, 3, 12));
    });

    test('a past calendar date is returned with a warning', () {
      final t = at('10 月 1 日 9 点')!;
      expect(t.at, DateTime(2026, 10, 1, 9));
      expect(t.warning, isNotNull);
    });

    test('no time at all', () {
      expect(at('随便吧'), isNull);
      expect(at(''), isNull);
    });

    test('impossible month rolls over instead of being accepted', () {
      expect(at('2 月 31 日 10 点'), isNull);
    });
  });
}
