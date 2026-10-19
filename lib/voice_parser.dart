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
  final List<String> settings;
  const ParsedVoice(this.reminder, this.hasTime, this.warning, this.reference, {this.relativeDelay, this.settings = const []});
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
  final controls = extractVoiceControls(body, r);
  body = controls.body;
  ParsedVoice result(bool hasTime, String? warning, {Duration? delay}) => ParsedVoice(
    r, hasTime, [if (warning != null) warning, if (controls.warning != null) controls.warning].join(' ').isEmpty
      ? null : [if (warning != null) warning, if (controls.warning != null) controls.warning].join(' '),
    current, relativeDelay: delay, settings: controls.settings);
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
      return result(true, null, delay: delay);
    }
    r.date = current; r.timeConfirmed = false;
    return result(false, '未能确定倒计时时长，请手动选择日期和时间。');
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
  if (!hasTime) warning = '未识别到有效时间，请重新录音或手动选择时间。';
  if (hasTime && r.repeat == 'none' && r.dateConfirmed && !date.isAfter(current)) {
    warning = '这个时间已经过去，请手动修改日期或时间；不会自动顺延。';
  }
  return result(hasTime, warning);
}


class VoiceControls {
  final String body;
  final List<String> settings;
  final String? warning;
  const VoiceControls(this.body, this.settings, this.warning);
}

// Consume only a suffix of explicit commands. A phrase inside a task remains content.
VoiceControls extractVoiceControls(String source, Reminder r) {
  var body = source.trim().replaceAll(RegExp(r'[。！？.!?\s]+$'), '');
  final settings = <String>[];
  var foundSpeech = false, foundSound = false, foundPrivacy = false;
  var foundInterval = false, foundCount = false;
  String? warning;
  const number = r'[零〇一二两三四五六七八九十百千万\d]+';
  final rules = <(RegExp, void Function(RegExpMatch))>[
    (RegExp('再提醒($number)次\$'), (_) {
      warning = '“再提醒几次”可能不包含首次，请改说“总共提醒几次”，或手动确认总次数。';
    }),
    (RegExp('(?:提醒间隔(?:为)?|(?:每隔|每|间隔)(?:为)?)($number)(?:个)?分钟(?:再)?(?:提醒(?:我)?)?\$'), (match) {
      if (foundInterval) return;
      final value = chineseNumber(match.group(1)!);
      if (value == null || value < 1 || value > 1440) {
        warning = '提醒间隔应为 1—1440 分钟，请重新说明或手动编辑。'; return;
      }
      r.intervalMinutes = value; foundInterval = true;
      settings.add('未确认时：每隔 $value 分钟提醒');
    }),
    (RegExp('(?:提醒(?:总共|一共|共)?|(?:总共|一共|共|总计)(?:提醒)?)($number)次(?:提醒)?(?:[（(]含首次[）)])?\$'), (match) {
      if (foundCount) return;
      final value = chineseNumber(match.group(1)!);
      if (value == null || value < 1 || value > 20) {
        warning = '提醒总次数应为 1—20 次（含首次），请重新说明或手动编辑。'; return;
      }
      r.totalCount = value; foundCount = true;
      settings.add('提醒次数：共 $value 次（含首次）');
    }),
    (RegExp(r'(?:不要|不用)(?:开启|打开|启用)?(?:语音提醒|语音播报|朗读提醒|读出来|念出来)$'), (_) { if (!foundSpeech) { r.speechMode = 'off'; foundSpeech = true; settings.add('语音播报：关闭'); } }),
    (RegExp(r'(?:关闭|取消|禁用)(?:语音提醒|语音播报|朗读提醒)$'), (_) { if (!foundSpeech) { r.speechMode = 'off'; foundSpeech = true; settings.add('语音播报：关闭'); } }),
    (RegExp(r'(?:(?:开启|打开|启用)(?:语音提醒|语音播报|朗读提醒)|到时候(?:读|念)出来)$'), (_) { if (!foundSpeech) { r.speechMode = 'on'; foundSpeech = true; settings.add('语音播报：开启'); } }),
    (RegExp(r'(?:语音提醒|语音播报)(?:跟随默认|使用默认设置)$'), (_) { if (!foundSpeech) { r.speechMode = 'inherit'; foundSpeech = true; settings.add('语音播报：跟随默认'); } }),
    (RegExp(r'(?:只振动|静音提醒|不发声|不要声音)$'), (match) { if (match.group(0) == '只振动' && r.vibration == 'off') r.vibration = 'three'; if (!foundSound) { r.sound = false; foundSound = true; } if (!foundSpeech) { r.speechMode = 'off'; foundSpeech = true; } settings.add('声音：静音'); }),
    (RegExp(r'(?:开启|打开|使用)(?:系统)?铃声(?:提醒)?$'), (_) { if (!foundSound) { r.sound = true; foundSound = true; settings.add('备用铃声：开启'); } }),
    (RegExp(r'(?:关闭|取消|不要)(?:系统)?铃声(?:提醒)?$'), (_) { if (!foundSound) { r.sound = false; foundSound = true; settings.add('备用铃声：关闭'); } }),
    (RegExp(r'锁屏(?:时)?(?:隐藏播报正文|隐藏播放内容|隐藏语音内容)$'), (_) { if (!foundPrivacy) { r.speechHideLocked = true; foundPrivacy = true; settings.add('锁屏播报：隐藏正文'); } }),
    (RegExp(r'锁屏(?:时)?(?:不隐藏播报正文|不隐藏播放内容|正常播报|朗读正文)$'), (_) { if (!foundPrivacy) { r.speechHideLocked = false; foundPrivacy = true; settings.add('锁屏播报：允许正文'); } }),
  ];
  while (true) {
    var consumed = false;
    for (final rule in rules) {
      final match = rule.$1.firstMatch(body);
      if (match == null) continue;
      final prefix = body.substring(0, match.start);
      if (RegExp(r'(?:如何|怎么|怎样|是否|能否|学习|研究|教程|方法|不要|不用|不想|不是|取消|关闭|别)(?:去)?$').hasMatch(prefix.trim())) {
        warning = '末尾可能属于待办正文，已保留；请手动确认提醒设置。';
        return VoiceControls(body, settings.reversed.toList(), warning);
      }
      // No reminder body means this could be the task itself, not a setting.
      if (prefix.replaceAll(RegExp(r'[，,；;。\s]'), '').isEmpty) continue;
      rule.$2(match);
      if (warning != null) return VoiceControls(body, settings.reversed.toList(), warning);
      body = prefix.replaceAll(RegExp(r'[，,；;。\s]+$'), '');
      consumed = true;
      break;
    }
    if (!consumed) break;
  }
  return VoiceControls(body, settings.reversed.toList(), warning);
}
