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

enum VoiceIssue { boundary, relativeReference, dependency, limit, scope }

class ParsedVoice {
  final Reminder reminder;
  final bool hasTime;
  final String? warning;
  final Duration? relativeDelay;
  final DateTime reference;
  final List<String> settings;
  final VoiceIssue? issue;
  final String? original, evidence;
  final List<ParsedVoice> alternatives;
  final DateTime? previousTime;
  const ParsedVoice(this.reminder, this.hasTime, this.warning, this.reference, {this.relativeDelay, this.settings = const [], this.issue, this.original, this.evidence,
    this.alternatives = const [], this.previousTime});
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

/// Multi-task boundaries are decisions, not every time entity found in a body.
/// Matching uses a compact, quote-masked view with offsets back to the original.
class _BatchText {
  final String original;
  final List<int> offsets = [];
  late final String text, mask;
  _BatchText(this.original) {
    final compact = StringBuffer(), hidden = StringBuffer(), quotes = <String>[];
    const pairs = {'“': '”', '「': '」', '『': '』', '《': '》', '"': '"'};
    for (var i = 0; i < original.length; i++) {
      var c = original[i];
      if (RegExp(r'\s').hasMatch(c)) continue;
      final code = c.codeUnitAt(0);
      if (code >= 0xff10 && code <= 0xff19) c = String.fromCharCode(code - 0xfee0);
      offsets.add(i); compact.write(c);
      if (quotes.isNotEmpty && c == quotes.last) { quotes.removeLast(); hidden.write(' '); }
      else if (pairs.containsKey(c)) { quotes.add(pairs[c]!); hidden.write(' '); }
      else { hidden.write(quotes.isEmpty ? c : ' '); }
    }
    text = compact.toString(); mask = hidden.toString(); offsets.add(original.length);
  }
  String slice(int start, int end) => original.substring(offsets[start], offsets[end]).trim();
}

const _batchNumber = r'[零〇一二两三四五六七八九十百千\d]+';
final _batchTime = RegExp('(?:(明早|明晚|今晚|今天|明天|后天|每天|每日|工作日|(?:每周|每星期|周|星期)[一二三四五六日天1-7]|(?:$_batchNumber年)?(?:$_batchNumber月)?$_batchNumber[日号])?'
  '(?:凌晨|午夜|早上|上午|中午|下午|傍晚|晚上)?(?:$_batchNumber[点时](?:半|一刻|三刻|$_batchNumber分?)?|\\d{1,2}[:：]\\d{1,2}(?:[:：]\\d{1,2})?)'
  '|(?:(?:$_batchNumber个半|一个半|$_batchNumber|半)(?:个)?(?:天|小时|分钟|分|秒钟|秒))+[以之]?后'
  '|再过(?:(?:$_batchNumber|半)(?:个)?(?:天|小时|分钟|分|秒钟|秒))+)');
final _batchJoin = RegExp(r'[，,；;。、]*(?:然后|另外|接着|还有|再)[，,；;。、]*$');
String _trimBatch(String value) => value.replaceAll(RegExp(r'^[，,；;。、：:\s]+|[，,；;。、\s]+$'), '').trim();

List<ParsedVoice> parseVoiceBatch(String source, {DateTime? now, required Reminder Function() defaults}) {
  final current = now ?? DateTime.now();
  ParsedVoice annotate(ParsedVoice p, {String? original, VoiceIssue? issue, String? warning,
    String? evidence, List<ParsedVoice> alternatives = const [], DateTime? previousTime}) => ParsedVoice(
      p.reminder, p.hasTime, warning ?? p.warning, p.reference, relativeDelay: p.relativeDelay, settings: p.settings,
      original: original, issue: issue, evidence: evidence, alternatives: alternatives, previousTime: previousTime);
  final view = _BatchText(source);
  // Explicit separators are recognised only in a command/list position. An
  // ordinary mention such as “阅读下一条通知” never becomes a separator.
  final separators = <RegExpMatch>[];
  final separator = RegExp(r'下一条|第[一二三四五六七八九十\d]+条');
  var numbered = false;
  for (final m in separator.allMatches(view.mask)) {
    final tail = view.mask.substring(m.end).replaceFirst(RegExp(r'^[，,；;。、：:]+'), '');
    final leading = m.start == 0 || RegExp(r'^[，,；;。、]*(?:请)?$').hasMatch(view.mask.substring(0, m.start));
    if (leading && m.group(0) != '下一条') numbered = true;
    final nextCommand = _batchTime.matchAsPrefix(tail) != null || tail.startsWith('提醒我') || tail.startsWith('提醒');
    if ((leading || nextCommand || tail.isEmpty) && (m.group(0) == '下一条' || numbered)) separators.add(m);
  }
  final ranges = <(int, int)>[];
  var begin = 0;
  for (final m in separators) {
    if (_trimBatch(view.slice(begin, m.start)).isNotEmpty) ranges.add((begin, m.start));
    begin = m.end;
  }
  if (_trimBatch(view.slice(begin, view.text.length)).isNotEmpty || separators.isNotEmpty) ranges.add((begin, view.text.length));
  if (ranges.isEmpty) ranges.add((0, view.text.length));
  var inheritedDate = '';
  final rows = <ParsedVoice>[];
  for (final range in ranges) {
    final raw = _trimBatch(view.slice(range.$1, range.$2));
    final v = _BatchText(raw);
    final prefix = RegExp(r'^[，,；;。、]*(?:先|首先)?(?:请)?(?:帮我|给我)?(?:设置|创建)?(?:提醒我|提醒)?[，,：:]*').firstMatch(v.mask)!;
    final times = _batchTime.allMatches(v.mask).where((m) => m.start >= prefix.end).toList();
    if (times.isEmpty || times.first.start != prefix.end || RegExp(r'(?:完成|结束|做完)后').hasMatch(v.mask)) {
      final p = parseVoice('提醒我$raw', now: current, defaults: defaults());
      p.reminder.text = raw.replaceFirst(RegExp(r'^提醒我|^提醒'), '');
      p.reminder.timeConfirmed = false;
      final dependent = RegExp(r'(?:完成|结束|做完)后').hasMatch(v.mask);
      rows.add(annotate(p, original: raw, issue: dependent ? VoiceIssue.dependency : null,
        warning: dependent ? '完成后计时需要任务依赖，请改为具体提醒时间。' : '这条尚未确定时间或内容，请编辑补全。'));
      continue;
    }
    final accepted = <RegExpMatch>[times.first];
    final starts = <int>[0];
    final weak = <int, RegExpMatch>{};
    var explicitBody = RegExp(r'^[，,：:]*(?:提醒我|提醒)').hasMatch(v.mask.substring(times.first.end));
    for (final t in times.skip(1)) {
      final before = v.mask.substring(accepted.last.end, t.start);
      final after = v.mask.substring(t.end);
      // Degree/quantity uses and attributive time references remain body text.
      final notSchedule = RegExp(r'^(?:点|的|钟的)').hasMatch(after) ||
        RegExp(r'(?:小|大|快|慢|早|晚|好|少|多|加|放|倒|有|剩|差)$').hasMatch(before) && t.group(0) == '一点' ||
        t.group(0) == '一点' && RegExp(r'^(?:盐|水|糖|油|儿|问题|事情)').hasMatch(after);
      if (notSchedule) continue;
      final join = _batchJoin.firstMatch(before);
      final reminder = RegExp(r'^[，,：:]*(?:提醒我|提醒)').hasMatch(after);
      final separated = RegExp(r'[，,；;。、]$').hasMatch(before);
      final referential = RegExp(r'(?:查看|阅读|整理|讨论|记录|学习|研究|关于|有关|在|到|从|等到|直到|持续|需要|提前)$').hasMatch(before);
      final body = before.replaceFirst(_batchJoin, '').replaceAll(RegExp(r'[，,；;。、]'), '');
      final strong = reminder && (join != null || separated) && !referential;
      final compactList = !explicitBody && !referential && (body.isNotEmpty || separated);
      if (strong || compactList || t.group(0)!.startsWith('再过')) {
        starts.add(join == null ? t.start : accepted.last.end + join.start);
        accepted.add(t); explicitBody = reminder;
      } else if (explicitBody && !referential && body.isNotEmpty && weak.isEmpty) {
        weak[accepted.length - 1] = t;
      }
    }
    ParsedVoice make(int start, int end, RegExpMatch t, String date, {bool inherit = true}) {
      final explicitDate = t.group(1);
      final schedule = t.group(0)!.replaceFirst(RegExp(r'^明早'), '明天早上')
        .replaceFirst(RegExp(r'^明晚'), '明天晚上').replaceFirst(RegExp(r'^今晚'), '今天晚上')
        .replaceFirst(RegExp(r'^再过'), '');
      final relative = t.group(0)!.startsWith('再过');
      final instruction = '${inherit && explicitDate == null && !schedule.endsWith('后') && !relative ? date : ''}$schedule${relative ? '后' : ''}';
      var body = v.slice(t.end, end).replaceFirst(RegExp(r'^[，,：:\s]*(?:提醒我|提醒)?[，,：:\s]*'), '');
      body = _trimBatch(body);
      final p = parseVoice('$instruction提醒我$body', now: current, defaults: defaults());
      // Parsing the schedule cannot consume or reinterpret a body time.
      return annotate(p, original: _trimBatch(v.slice(start, end)));
    }
    for (var i = 0; i < accepted.length; i++) {
      final t = accepted[i], end = i + 1 < starts.length ? starts[i + 1] : v.text.length;
      final date = t.group(1);
      if (date != null) inheritedDate = switch (date) { '明早' || '明晚' => '明天', '今晚' => '今天', _ => date };
      var p = make(starts[i], end, t, inheritedDate);
      if (t.group(0)!.startsWith('再过')) {
        p = annotate(p, original: p.original, issue: VoiceIssue.relativeReference,
          warning: '“再过”从录音时刻还是上一条计划时间起算？请选择。', previousTime: rows.isEmpty ? null : rows.last.reminder.date);
      } else if (weak.containsKey(i) && weak[i]!.start < end) {
        final w = weak[i]!;
        p = annotate(p, original: p.original, issue: VoiceIssue.boundary, evidence: v.slice(w.start, end),
          warning: '正文中发现另一处时间，尚未自动拆分。请确认是一条还是两条。',
          alternatives: [make(starts[i], w.start, t, inheritedDate), make(w.start, end, w, inheritedDate)]);
      }
      if (RegExp(r'(?:这些|这[两几]条|全部|所有).*(?:开启|关闭)语音播报').hasMatch(v.slice(t.end, end))) {
        p = annotate(p, original: p.original, issue: VoiceIssue.scope, warning: '检测到批量设置，请逐条确认语音播报开关。');
      }
      rows.add(p);
    }
  }
  if (rows.length > 10) {
    final r = defaults()..text = source..timeConfirmed = false;
    return [ParsedVoice(r, false, '一次最多核对10条提醒，请减少条数后重新录入；原文完整保留。', current, issue: VoiceIssue.limit, original: source)];
  }
  return rows;
}
