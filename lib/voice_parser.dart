import 'reminder.dart';

int? chineseNumber(String source) {
  final s = source.replaceAll('两', '二').replaceAll('〇', '零');
  if (RegExp(r'^\d+$').hasMatch(s)) return int.tryParse(s);
  const digits = {'零': 0, '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9};
  if (s.isEmpty) return null;
  if (!RegExp('[十百千]').hasMatch(s)) {
    var value = 0;
    for (final c in s.split('')) {
      if (!digits.containsKey(c)) return null;
      value = value * 10 + digits[c]!;
    }
    return value;
  }
  var value = 0, pending = 0, previousUnit = 10000;
  for (final c in s.split('')) {
    if (digits.containsKey(c)) { pending = digits[c]!; continue; }
    final unit = {'十': 10, '百': 100, '千': 1000}[c];
    if (unit == null || unit >= previousUnit) return null;
    value += (pending == 0 ? 1 : pending) * unit;
    pending = 0; previousUnit = unit;
  }
  return value + pending;
}

class ParsedVoice {
  final Reminder reminder;
  final bool hasTime;
  final String? warning;
  final Duration? relativeDelay;
  final DateTime reference;
  const ParsedVoice(this.reminder, this.hasTime, this.warning, this.reference, {this.relativeDelay});
}

// Only the instruction before “提醒我” controls scheduling. The reminder body
// may contain dates, book titles, or words such as 每天 without changing it.
ParsedVoice parseVoice(String source, {DateTime? now, Reminder? defaults}) {
  final current = DateTime.fromMillisecondsSinceEpoch((now ?? DateTime.now()).millisecondsSinceEpoch);
  final r = defaults ?? Reminder();
  r.repeat = 'none'; r.days = [];
  r.dateConfirmed = true; r.timeConfirmed = true;
  final marker = RegExp(r'提醒我|提醒').firstMatch(source);
  var instruction = marker == null ? source : source.substring(0, marker.start);
  var body = marker == null ? source : source.substring(marker.end);
  const n = r'[零〇一二两三四五六七八九十百千\d]+';
  // Also accept “提醒我五分钟后喝水”, but only a leading duration.
  if (instruction.trim().isEmpty && marker != null) {
    final leading = RegExp('^\\s*((?:(?:$n|半|一个半|$n个半)(?:个)?(?:天|小时|分钟|分|秒钟|秒))+[以之]?后)[，,、\\s]*').firstMatch(body);
    if (leading != null) { instruction = leading.group(1)!; body = body.substring(leading.end); }
    else {
      final absolute = RegExp('^\\s*((?:(?:$n年)?(?:$n月)?$n[号日]|今天|明天|后天|每天|每日|工作日|(?:每周|每星期|周|星期)[一二三四五六日天1-7])?(?:凌晨|午夜|早上|上午|中午|下午|傍晚|晚上)?(?:$n[点时](?:半|一刻|三刻|$n分?)?|\\d{1,2}[:：]\\d{1,2}(?:[:：]\\d{1,2})?))[，,、\\s]*').firstMatch(body);
      if (absolute != null) { instruction = absolute.group(1)!; body = body.substring(absolute.end); }
    }
  }
  final s = instruction.replaceAll(RegExp(r'[\s，,。]'), '');
  r.text = body.replaceAll(RegExp(r'^[，,、\s]+|[，。！？、,.!?\s]+$'), '').trim();
  final durationMatch = RegExp(r'^(.*?)(?:以后|之后|后)$').firstMatch(s);
  if (durationMatch != null) {
    final durationText = durationMatch.group(1)!;
    final pieces = RegExp('($n个半|一个半|$n|半)(?:个)?(天|小时|分钟|分|秒钟|秒)').allMatches(durationText).toList();
    var end = 0, millis = 0;
    final units = <String>{};
    var valid = pieces.isNotEmpty;
    for (final p in pieces) {
      if (p.start != end || !units.add(p.group(2)!.replaceAll('钟', ''))) valid = false;
      final number = p.group(1)!;
      final double? amount = number == '半' ? 0.5 : number.endsWith('个半')
        ? (chineseNumber(number.substring(0, number.length - 2))?.toDouble() ?? -100) + 0.5
        : chineseNumber(number)?.toDouble();
      final factor = switch (p.group(2)) {
        '天' => 86400000, '小时' => 3600000, '分钟' || '分' => 60000, _ => 1000,
      };
      if (amount == null || amount <= 0) { valid = false; }
      else { millis += (amount * factor).round(); }
      end = p.end;
    }
    valid = valid && end == durationText.length && millis > 0 && millis <= 86400000 * 3650;
    if (valid) {
      final delay = Duration(milliseconds: millis);
      r.date = current.add(delay);
      return ParsedVoice(r, true, null, current, relativeDelay: delay);
    }
    r.date = current; r.timeConfirmed = false;
    return ParsedVoice(r, false, '未能确定倒计时时长，请手动选择日期和时间。', current);
  }
  final clock = RegExp('($n)[点时](半|一刻|三刻|($n)分?)?').firstMatch(s);
  final colon = RegExp(r'(\d{1,2})[:：](\d{1,2})(?:[:：](\d{1,2}))?').firstMatch(s);
  int? hour = clock == null ? null : chineseNumber(clock.group(1)!);
  var minute = 0, second = 0;
  if (clock != null) {
    minute = switch (clock.group(2)) {
      '半' => 30, '一刻' => 15, '三刻' => 45,
      _ => chineseNumber(clock.group(3) ?? '零') ?? 60,
    };
  } else if (colon != null) {
    hour = int.parse(colon.group(1)!); minute = int.parse(colon.group(2)!);
    second = int.parse(colon.group(3) ?? '0');
  }
  if (hour != null && RegExp('下午|晚上|傍晚').hasMatch(s) && hour < 12) hour += 12;
  if (hour == 12 && RegExp('凌晨|午夜').hasMatch(s)) hour = 0;
  final hasTime = hour != null && hour >= 0 && hour < 24 && minute < 60 && second < 60;
  r.timeConfirmed = hasTime;
  var date = DateTime(current.year, current.month, current.day,
    hasTime ? hour : current.hour, hasTime ? minute : current.minute, hasTime ? second : current.second);
  var explicitDate = false;
  String? warning;
  if (s.contains('后天')) { date = DateTime(date.year, date.month, date.day + 2, date.hour, date.minute, date.second); explicitDate = true; }
  else if (s.contains('明天')) { date = DateTime(date.year, date.month, date.day + 1, date.hour, date.minute, date.second); explicitDate = true; }
  else if (s.contains('今天')) { explicitDate = true; }
  final monthDay = RegExp('(?:($n)年)?(?:($n)月)?($n)[号日]').firstMatch(s);
  if (monthDay != null) {
    final year = chineseNumber(monthDay.group(1) ?? '${current.year}');
    final month = chineseNumber(monthDay.group(2) ?? '${current.month}');
    final day = chineseNumber(monthDay.group(3)!);
    explicitDate = true;
    if (year != null && month != null && day != null && year >= 1970 && year <= 2200 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      final candidate = DateTime(year, month, day, date.hour, date.minute, date.second);
      if (candidate.month == month && candidate.day == day) { date = candidate; }
      else { r.dateConfirmed = false; }
    } else { r.dateConfirmed = false; }
    if (!r.dateConfirmed) warning = '日期无效，请手动选择日期；不会自动顺延到下个月。';
  }
  if (s.contains('每天') || s.contains('每日')) r.repeat = 'daily';
  final week = RegExp(r'(每周|每星期|周|星期)([一二三四五六日天1-7])').firstMatch(s);
  if (s.contains('工作日')) {
    r.repeat = 'weekly'; r.days = [1, 2, 3, 4, 5];
  } else if (week != null) {
    final day = '日天'.contains(week.group(2)!) ? 7 : chineseNumber(week.group(2)!)!;
    r.repeat = week.group(1)!.startsWith('每') ? 'weekly' : 'none'; r.days = [day];
    var delta = (day - current.weekday + 7) % 7;
    if (delta == 0 && !date.isAfter(current)) delta = 7;
    date = DateTime(current.year, current.month, current.day + delta, date.hour, date.minute, date.second);
    explicitDate = true;
  }
  if (!explicitDate && hasTime && !date.isAfter(current)) date = DateTime(date.year, date.month, date.day + 1, date.hour, date.minute, date.second);
  r.date = date;
  if (!hasTime) warning = '未识别到有效时间，请在下一页手动选择时间。';
  if (hasTime && r.repeat == 'none' && r.dateConfirmed && !date.isAfter(current)) {
    warning = '这个时间已经过去，请手动修改日期或时间；不会自动顺延。';
  }
  return ParsedVoice(r, hasTime, warning, current);
}
