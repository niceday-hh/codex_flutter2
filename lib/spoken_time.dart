import 'voice_parser.dart' show chineseNumber;

/// A scheduling phrase that stands on its own.
///
/// [parseVoice] expects a whole utterance and splits it at “提醒我”. This is the
/// other entry point: a time sheet whose only input is “明天下午三点” or
/// “30 分钟后”. It reuses [chineseNumber] but not the body-splitting rules,
/// because there is no body to split — and no reminder to create, only an
/// instant to move something to.
class SpokenTime {
  final DateTime at;

  /// The phrase was a duration, so the result depends on when it was spoken.
  /// The sheet says “已按当前时间推算” instead of claiming a calendar date.
  final bool relative;

  /// Set when an explicit calendar date is in the past. The instant is still
  /// returned: the sheet shows the warning and disables “确定”, so the user is
  /// never silently moved to a time the parser invented.
  final String? warning;

  const SpokenTime(this.at, {this.relative = false, this.warning});
}

const _number = r'[零〇一二两三四五六七八九十百千\d]+';

/// Punctuation between words. Colons are deliberately kept: “21:40” loses its
/// meaning the moment they are stripped.
final _noise = RegExp(r'[\s，。！？、；,.!?;]');

/// Verbs and filler that may precede the time itself. Applied repeatedly so
/// “帮我把提醒改到明天九点” reduces to “明天九点”.
///
/// One particle at a time, because a single alternation match only consumes the
/// leftmost branch; looping is what unwraps a stack of polite prefixes.
final _lead = RegExp(
  r'^(?:请|麻烦|帮我|给我|把|将|我的|提醒我|提醒|闹钟|时间|它|'
  r'改到|改成|改在|改为|换到|换成|调到|调成|挪到|推到|推迟到|延迟到|延后到|'
  r'往后推|往后|推迟|延迟|延后|提前到|提前|定在|定到|设为|设成|设置成|设置到|到|在|就)');

String _trimLeads(String source) {
  var out = source;
  for (var i = 0; i < 8; i++) {
    final next = out.replaceFirst(_lead, '');
    if (next == out) break;
    out = next;
  }
  return out;
}

double? _amount(String text) {
  if (text == '半') return .5;
  if (text == '一个半') return 1.5;
  if (text.endsWith('个半')) {
    final value = chineseNumber(text.substring(0, text.length - 2));
    return value == null ? null : value + .5;
  }
  return chineseNumber(text)?.toDouble();
}

/// “30 分钟后”, “一个半小时以后”, “延后 20 分钟”.
///
/// [from] is the time already selected in the sheet, so a second “再晚 10 分钟”
/// stacks on what the user is looking at instead of jumping back to now. A
/// selection in the past is ignored — adding to it would only produce another
/// past instant.
SpokenTime? _duration(String text, DateTime now, DateTime? from) {
  // Repeating, because “再晚 20 分钟” stacks two particles before the number.
  final match = RegExp('^(?:(?:再|延后|延迟|推迟|往后|晚|多))*'
      '($_number个半|一个半|$_number|半)(?:个)?'
      '(天|小时|分钟|分|秒钟|秒)(?:以后|之后|后)?\$').firstMatch(text);
  if (match == null) return null;
  final amount = _amount(match.group(1)!);
  if (amount == null || amount <= 0) return null;
  final factor = switch (match.group(2)) {
    '天' => 86400000,
    '小时' => 3600000,
    '分钟' || '分' => 60000,
    _ => 1000,
  };
  final millis = (amount * factor).round();
  if (millis <= 0 || millis > 86400000 * 3650) return null;
  final base = from != null && from.isAfter(now) ? from : now;
  return SpokenTime(base.add(Duration(milliseconds: millis)), relative: true);
}

({int hour, int minute, int second})? _clock(String text) {
  final spoken = RegExp('($_number)[点时](半|一刻|三刻|($_number)分?)?').firstMatch(text);
  final colon = RegExp(r'(\d{1,2})[:：](\d{1,2})(?:[:：](\d{1,2}))?').firstMatch(text);
  int? hour;
  var minute = 0, second = 0;
  if (spoken != null) {
    hour = chineseNumber(spoken.group(1)!);
    minute = switch (spoken.group(2)) {
      '半' => 30,
      '一刻' => 15,
      '三刻' => 45,
      _ => chineseNumber(spoken.group(3) ?? '零') ?? 0,
    };
  } else if (colon != null) {
    hour = int.tryParse(colon.group(1)!);
    minute = int.tryParse(colon.group(2)!) ?? 0;
    second = int.tryParse(colon.group(3) ?? '0') ?? 0;
  }
  if (hour == null || hour < 0 || hour > 23) return null;
  if (minute < 0 || minute > 59 || second < 0 || second > 59) return null;
  return (hour: hour, minute: minute, second: second);
}

/// “下午三点” is 15:00, “晚上十二点” is 00:00, “凌晨十二点” is also 00:00.
int _hourOfDay(int hour, String text) {
  if (RegExp('下午|傍晚').hasMatch(text) && hour < 12) return hour + 12;
  if (RegExp('晚上|夜里|夜').hasMatch(text)) {
    if (hour == 12) return 0;
    if (hour < 12) return hour + 12;
  }
  if (text.contains('中午') && hour < 11) return hour + 12;
  if (RegExp('凌晨|半夜|午夜').hasMatch(text) && hour == 12) return 0;
  return hour;
}

/// Parses a standalone scheduling phrase.
///
/// Returns null only when no time was recognised at all. A recognised but
/// already-past calendar date still returns an instant, carrying [SpokenTime.warning]
/// so the caller can show it rather than pretend the phrase was unheard.
SpokenTime? parseSpokenTime(String source, {DateTime? now, DateTime? from, DateTime? preferDate}) {
  final current = now ?? DateTime.now();
  final text = _trimLeads(source.replaceAll(_noise, ''));
  if (text.isEmpty) return null;

  final duration = _duration(text, current, from);
  if (duration != null) return duration;

  final clock = _clock(text);
  if (clock == null) return null;
  final hour = _hourOfDay(clock.hour, text);

  var day = DateTime(current.year, current.month, current.day);
  var explicit = false;
  var weekday = 0;
  if (text.contains('大后天')) {
    day = day.add(const Duration(days: 3));
    explicit = true;
  } else if (text.contains('后天')) {
    day = day.add(const Duration(days: 2));
    explicit = true;
  } else if (text.contains('明天') || text.contains('明日')) {
    day = day.add(const Duration(days: 1));
    explicit = true;
  } else if (text.contains('今天') || text.contains('今日')) {
    explicit = true;
  }

  final week = RegExp(r'(?:周|星期|礼拜)([一二三四五六日天1-7])').firstMatch(text);
  String? warning;
  if (!explicit && week != null) {
    weekday = '日天'.contains(week.group(1)!) ? 7 : chineseNumber(week.group(1)!)!;
    explicit = true;
  }

  final monthDay = RegExp('(?:($_number)年)?(?:($_number)月)?($_number)[号日]').firstMatch(text);
  if (!explicit && monthDay != null) {
    final year = monthDay.group(1) == null ? current.year : chineseNumber(monthDay.group(1)!)!;
    final month = monthDay.group(2) == null ? current.month : chineseNumber(monthDay.group(2)!)!;
    final date = chineseNumber(monthDay.group(3)!)!;
    if (month < 1 || month > 12 || date < 1 || date > 31) return null;
    final candidate = DateTime(year, month, date);
    // Day 31 of a 30-day month rolls over in Dart; reject instead of silently
    // reminding on the 1st of the next month.
    if (candidate.month != month || candidate.day != date) return null;
    day = candidate;
    explicit = true;
  }

  if (!explicit) {
    final preferred = preferDate ?? current;
    day = DateTime(preferred.year, preferred.month, preferred.day);
  }

  var at = DateTime(day.year, day.month, day.day, hour, clock.minute, clock.second);
  if (weekday > 0) {
    at = at.add(Duration(days: (weekday - current.weekday + 7) % 7));
    if (!at.isAfter(current)) at = at.add(const Duration(days: 7));
  } else if (monthDay != null) {
    if (!at.isAfter(current)) warning = '这个日期已经过去，请说一个更晚的时间';
  } else if (!explicit && !at.isAfter(current)) {
    // “九点” said at 20:00 means tomorrow; the sheet is for future reminders,
    // so rolling forward is the only reading that can be applied.
    at = at.add(const Duration(days: 1));
  }

  return SpokenTime(at, warning: warning);
}
