import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/voice_parser.dart';

void main() {
  final now = DateTime(2026, 10, 16, 22, 23, 4);
  test('interval, total attempts, and speech become separate reminder fields', () {
    final p = parseVoice('五分钟后提醒我喝水，提醒间隔三分钟，提醒五次，开启语音播报', now: now);
    expect(p.reminder.text, '喝水');
    expect(p.reminder.intervalMinutes, 3); expect(p.reminder.totalCount, 5);
    expect(p.reminder.speechMode, 'on'); expect(p.warning, isNull);
    expect(p.settings, contains('提醒次数：共 5 次（含首次）'));
  });
  test('unpunctuated retry controls accept Arabic and Chinese numbers and last values win', () {
    final p = parseVoice('五分钟后提醒我休息一下眼睛每隔两分钟提醒总共提醒十次提醒间隔3分钟共5次', now: now);
    expect(p.reminder.text, '休息一下眼睛');
    expect(p.reminder.intervalMinutes, 3); expect(p.reminder.totalCount, 5);
    expect(p.warning, isNull);
  });
  test('ambiguous additional attempts and invalid ranges are preserved for manual review', () {
    for (final suffix in ['再提醒五次', '提醒间隔零分钟', '提醒间隔1441分钟', '共二十一次', '不要提醒五次']) {
      final p = parseVoice('五分钟后提醒我喝水，$suffix', now: now);
      expect(p.warning, isNotNull, reason: suffix);
      expect(p.reminder.text, contains(suffix));
    }
  });
  test('retry words inside content never change reminder controls', () {
    final p = parseVoice('五分钟后提醒我研究如何提醒五次', now: now,
      defaults: Reminder(intervalMinutes: 8, totalCount: 2));
    expect(p.reminder.text, '研究如何提醒五次'); expect(p.reminder.totalCount, 2);
    expect(p.reminder.intervalMinutes, 8); expect(p.warning, isNotNull);
    expect(parseVoice('五分钟后提醒我阅读每隔三分钟提醒的说明书', now: now).reminder.text, '阅读每隔三分钟提醒的说明书');
  });
  test('relative time and explicit speech command are separate fields', () {
    final p = parseVoice('二十分钟后提醒我做饭，开启语音提醒', now: now, defaults: Reminder(speechMode: 'inherit'));
    expect(p.reminder.date, now.add(const Duration(minutes: 20)));
    expect(p.reminder.text, '做饭'); expect(p.reminder.speechMode, 'on');
    expect(p.settings, contains('语音播报：开启'));
  });
  test('unpunctuated ASR suffix, negative command, and last command win', () {
    expect(parseVoice('五分钟后提醒我喝水开启语音提醒', now: now).reminder.text, '喝水');
    final p = parseVoice('五分钟后提醒我喝水，开启语音提醒，不要开启语音提醒', now: now);
    expect(p.reminder.text, '喝水'); expect(p.reminder.speechMode, 'off');
    expect(parseVoice('五分钟后提醒我喝水，关闭语音播报，开启语音提醒', now: now).reminder.speechMode, 'on');
  });
  test('missing speech instruction retains default inheritance', () {
    final p = parseVoice('五分钟后提醒我喝水', now: now, defaults: Reminder(speechMode: 'inherit', sound: false));
    expect(p.reminder.speechMode, 'inherit'); expect(p.reminder.sound, isFalse);
  });
  test('research topic is not stripped or interpreted as a command', () {
    final p = parseVoice('明天九点提醒我研究如何开启语音提醒', now: now, defaults: Reminder(speechMode: 'inherit'));
    expect(p.reminder.text, '研究如何开启语音提醒'); expect(p.reminder.speechMode, 'inherit'); expect(p.warning, isNotNull);
  });
  test('lockscreen speech privacy and sound remain independent', () {
    final p = parseVoice('五分钟后提醒我喝水，开启语音提醒，锁屏时正常播报，关闭铃声', now: now);
    expect(p.reminder.text, '喝水'); expect(p.reminder.speechMode, 'on');
    expect(p.reminder.speechHideLocked, isFalse); expect(p.reminder.sound, isFalse);
    expect(parseVoice('五分钟后提醒我喝水，只振动', now: now, defaults: Reminder(vibration: 'off')).reminder.vibration, 'three');
    expect(parseVoice('五分钟后提醒我喝水，静音提醒', now: now, defaults: Reminder(speechMode: 'on')).reminder.speechMode, 'off');
  });
  test('speech data roundtrips and old reminders keep speech disabled', () {
    final r = Reminder(speechMode: 'on', speechVoice: '173', speechRate: 1.3, speechHideLocked: false, speechRepeat: false);
    final copy = Reminder.fromJson(r.toJson());
    expect(copy.speechMode, 'on'); expect(copy.speechVoice, '173'); expect(copy.speechRate, 1.3);
    expect(copy.speechHideLocked, isFalse); expect(copy.speechRepeat, isFalse);
    final old = r.toJson()..removeWhere((key, _) => key.startsWith('speech'));
    expect(Reminder.fromJson(old).speechMode, 'off');
    expect(MemoStore().draft().speechMode, 'inherit');
  });
}
