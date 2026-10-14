import 'reminder.dart';

int? chineseNumber(String source) {
  final s = source.replaceAll('两', '二').replaceAll('〇', '零');
  if (RegExp(r'^\d+$').hasMatch(s)) return int.tryParse(s);
  const map = {'零': 0, '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9};
  if (s.contains('十')) {
    final parts = s.split('十');
    if (parts.length != 2) return null;
    final tens = parts[0].isEmpty ? 1 : map[parts[0]];
    final ones = parts[1].isEmpty ? 0 : map[parts[1]];
    return tens == null || ones == null ? null : tens * 10 + ones;
  }
  if (s.length == 1) return map[s];
  if (s.length == 2 && map.containsKey(s[0]) && map.containsKey(s[1])) {
    return map[s[0]]! * 10 + map[s[1]]!;
  }
  return null;
}

class ParsedVoice {
  final Reminder reminder;
  final bool hasTime;
  final String? warning;
  const ParsedVoice(this.reminder, this.hasTime, this.warning);
}

ParsedVoice parseVoice(String source, {DateTime? now, Reminder? defaults}) {
  final current = now ?? DateTime.now();
  final r = defaults ?? Reminder();
  final s = source.replaceAll(RegExp(r'\s'), '');
  const n = r'[零〇一二两三四五六七八九十\d]+';
  final clock = RegExp('($n)[点时](半|一刻|三刻|($n)分?)?').firstMatch(s);
  final colon = RegExp(r'(\d{1,2})[:：](\d{2})').firstMatch(s);
  int? hour = clock == null ? null : chineseNumber(clock.group(1)!);
  var minute = 0;
  if (clock != null) {
    minute = switch (clock.group(2)) {
      '半' => 30, '一刻' => 15, '三刻' => 45,
      _ => chineseNumber(clock.group(3) ?? '零') ?? 0,
    };
  } else if (colon != null) {
    hour = int.parse(colon.group(1)!);
    minute = int.parse(colon.group(2)!);
  }
  if (hour != null && (s.contains('下午') || s.contains('晚上') || s.contains('傍晚')) && hour < 12) hour += 12;
  if (hour == 12 && (s.contains('凌晨') || s.contains('午夜'))) hour = 0;
  final hasTime = hour != null && hour < 24 && minute < 60;
  var date = DateTime(current.year, current.month, current.day,
    hasTime ? hour! : current.hour + 1, hasTime ? minute : 0);
  bool explicitDate = false;
  if (s.contains('后天')) { date = date.add(const Duration(days: 2)); explicitDate = true; }
  else if (s.contains('明天')) { date = date.add(const Duration(days: 1)); explicitDate = true; }
  else if (s.contains('今天')) { explicitDate = true; }
  final monthDay = RegExp('(?:($n)月)?($n)[号日]').firstMatch(s);
  if (monthDay != null && !s.contains('星期日') && !s.contains('周日')) {
    final m = chineseNumber(monthDay.group(1) ?? '${current.month}');
    final d = chineseNumber(monthDay.group(2)!);
    if (m != null && d != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      final candidate = DateTime(current.year, m, d, date.hour, date.minute);
      if (candidate.month == m && candidate.day == d) {
        date = candidate; explicitDate = true;
        if (!date.isAfter(current)) {
          date = monthDay.group(1) != null
            ? DateTime(current.year + 1, m, d, date.hour, date.minute)
            : DateTime(current.year, m + 1, d, date.hour, date.minute);
        }
      }
    }
  }
  if (s.contains('每天') || s.contains('每日')) r.repeat = 'daily';
  final week = RegExp(r'(每周|每星期|周|星期)([一二三四五六日天1-7])').firstMatch(s);
  if (s.contains('工作日')) {
    r.repeat = 'weekly'; r.days = [1, 2, 3, 4, 5];
  } else if (week != null) {
    final day = '日天'.contains(week.group(2)!) ? 7 : chineseNumber(week.group(2)!)!;
    r.repeat = week.group(1)!.startsWith('每') ? 'weekly' : 'none';
    r.days = [day];
    var delta = (day - current.weekday + 7) % 7;
    if (delta == 0 && !date.isAfter(current)) delta = 7;
    date = DateTime(current.year, current.month, current.day + delta, date.hour, date.minute);
    explicitDate = true;
  }
  if (!explicitDate && !date.isAfter(current)) date = date.add(const Duration(days: 1));
  r.date = date;
  final content = RegExp(r'(?:提醒我|提醒)(.+)').firstMatch(source);
  r.text = (content?.group(1) ?? source).replaceAll(RegExp(r'[，。！？、,.!?]+$'), '').trim();
  return ParsedVoice(r, hasTime, hasTime ? null : '未识别到明确时间，请在下一页确认日期和时间。');
}
