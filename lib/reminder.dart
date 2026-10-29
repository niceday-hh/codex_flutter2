import 'dart:convert';
import 'voice_group.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'speech.dart';

const native = MethodChannel('memo/native');
const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

class Reminder {
  int id;
  String text;
  DateTime date;
  String repeat;
  List<int> days;
  bool enabled, sound, wakeScreen;
  String vibration, ringtone, presentation, lockscreen;
  String speechMode, speechVoice, speechState;
  double speechRate, speechNoiseScale, speechNoiseScaleW;
  int speechSeed;
  bool speechHideLocked, speechRepeat, speechRandom;
  String speechRandomLanguage, speechRandomGender, speechRandomGroup;
  int intervalMinutes, totalCount;
  int attempts, activeOccurrence, nextTrigger;
  bool acknowledged, completed, archived;
  int archivedAt, lastAck, historyScheduledAt;
  // Draft-only validation flags; never written to a backup or native schedule.
  bool dateConfirmed = true, timeConfirmed = true;

  Reminder({this.id = 0, this.text = '', DateTime? date,
    this.repeat = 'none', List<int>? days, this.enabled = true,
    this.sound = true, this.wakeScreen = true, this.vibration = 'three',
    this.ringtone = '', this.intervalMinutes = 5, this.totalCount = 3,
    this.presentation = 'banner', this.lockscreen = 'private',
    this.speechMode = 'off', this.speechVoice = '', this.speechRate = 0,
    this.speechNoiseScale = 0, this.speechNoiseScaleW = 0, this.speechSeed = 0,
    this.speechHideLocked = true, this.speechRepeat = true, this.speechState = 'off',
    this.speechRandom = false, this.speechRandomLanguage = 'all', this.speechRandomGender = 'all', this.speechRandomGroup = '',
    this.attempts = 0, this.activeOccurrence = 0, this.nextTrigger = 0,
    this.acknowledged = false, this.completed = false, this.archived = false,
    this.archivedAt = 0, this.lastAck = 0, this.historyScheduledAt = 0})
      : date = date ?? DateTime.now().add(const Duration(hours: 1)),
        days = days ?? [];

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    id: j['id'] as int? ?? 0, text: j['text'] as String? ?? '',
    date: DateTime(j['year'] as int, j['month'] as int, j['day'] as int,
      j['hour'] as int, j['minute'] as int, j['second'] as int? ?? 0, j['millisecond'] as int? ?? 0),
    repeat: j['repeat'] as String? ?? 'none',
    days: (j['days'] as List? ?? []).cast<int>(),
    enabled: j['enabled'] as bool? ?? true,
    sound: j['sound'] as bool? ?? true,
    wakeScreen: j['wakeScreen'] as bool? ?? true,
    vibration: j['vibration'] as String? ?? 'three',
    ringtone: j['ringtone'] as String? ?? '',
    presentation: j['presentation'] as String? ?? 'banner',
    lockscreen: j['lockscreen'] as String? ?? 'private',
    speechMode: j['speechMode'] as String? ?? 'off',
    speechVoice: j['speechVoice'] as String? ?? '',
    speechRate: (j['speechRate'] as num?)?.toDouble() ?? 0,
    speechNoiseScale: (j['speechNoiseScale'] as num?)?.toDouble() ?? 0,
    speechNoiseScaleW: (j['speechNoiseScaleW'] as num?)?.toDouble() ?? 0,
    speechSeed: (j['speechSeed'] as num?)?.toInt() ?? 0,
    speechHideLocked: j['speechHideLocked'] as bool? ?? true,
    speechRepeat: j['speechRepeat'] as bool? ?? true,
    speechState: j['speechState'] as String? ?? 'off',
    speechRandom: j['speechRandom'] as bool? ?? false,
    speechRandomLanguage: j['speechRandomLanguage'] as String? ?? 'all',
    speechRandomGender: j['speechRandomGender'] as String? ?? 'all',
    speechRandomGroup: j['speechRandomGroup'] as String? ?? '',
    intervalMinutes: j['intervalMinutes'] as int? ?? 5,
    totalCount: j['totalCount'] as int? ?? 3,
    attempts: j['attempts'] as int? ?? 0,
    activeOccurrence: j['activeOccurrence'] as int? ?? 0,
    nextTrigger: j['nextTrigger'] as int? ?? 0,
    acknowledged: j['acknowledged'] as bool? ?? false,
    completed: j['completed'] as bool? ?? false,
    archived: j['archived'] as bool? ?? false,
    historyScheduledAt: (j['historyScheduledAt'] as num?)?.toInt() ?? 0,
    archivedAt: j['archivedAt'] as int? ?? 0, lastAck: j['lastAck'] as int? ?? 0,
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'text': text, 'year': date.year, 'month': date.month,
    'day': date.day, 'hour': date.hour, 'minute': date.minute,
    'second': date.second, 'millisecond': date.millisecond,
    'repeat': repeat, 'days': days, 'enabled': enabled,
    'sound': sound, 'wakeScreen': wakeScreen, 'vibration': vibration,
    'ringtone': ringtone, 'intervalMinutes': intervalMinutes,
    'totalCount': totalCount,
    'presentation': presentation, 'lockscreen': lockscreen,
    'speechMode': speechMode, 'speechVoice': speechVoice, 'speechRate': speechRate,
    'speechNoiseScale': speechNoiseScale, 'speechNoiseScaleW': speechNoiseScaleW, 'speechSeed': speechSeed,
    'speechRandom': speechRandom, 'speechRandomLanguage': speechRandomLanguage, 'speechRandomGender': speechRandomGender, 'speechRandomGroup': speechRandomGroup,
    'speechHideLocked': speechHideLocked, 'speechRepeat': speechRepeat,
    'speechModel': 'voine-vits-mnn-v1',
    'archived': archived, 'archivedAt': archivedAt,
  };
  Map<String, dynamic> get notificationConfig => {
    'sound': sound, 'vibration': vibration, 'ringtone': ringtone,
    'presentation': presentation, 'lockscreen': lockscreen,
    'speechMode': speechMode, 'speechVoice': speechVoice, 'speechRate': speechRate,
    'speechNoiseScale': speechNoiseScale, 'speechNoiseScaleW': speechNoiseScaleW, 'speechSeed': speechSeed,
    'speechRandom': speechRandom, 'speechRandomLanguage': speechRandomLanguage, 'speechRandomGender': speechRandomGender, 'speechRandomGroup': speechRandomGroup,
    'speechHideLocked': speechHideLocked, 'speechRepeat': speechRepeat,
  };
  String get time => '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  String get preciseTime => '$time:${date.second.toString().padLeft(2, '0')}';
  String get repeatLabel => switch (repeat) {
    'daily' => '每天',
    'weekly' => '每周${(List<int>.of(days)..sort()).map((d) => weekdays[d - 1]).join('、')}',
    _ => '仅一次',
  };
  bool get unread => activeOccurrence > 0 && !acknowledged;
  DateTime get displayDate => DateTime.fromMillisecondsSinceEpoch(
    unread ? activeOccurrence : (nextTrigger > 0 ? nextTrigger : date.millisecondsSinceEpoch));
}

class MemoStore extends ChangeNotifier {
  List<Reminder> reminders = [];
  List<VoiceGroup> voiceGroups = [];
  Map<String, dynamic> defaults = {};
  Map<String, dynamic> status = {};
  Future<void> load() async {
    final raw = await native.invokeMethod<String>('getState');
    final j = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
    reminders = (j['reminders'] as List? ?? [])
      .map((v) => Reminder.fromJson(Map<String, dynamic>.from(v as Map))).toList();
    voiceGroups = (j['voiceGroups'] as List? ?? []).map((g) => VoiceGroup.fromJson(Map<String, dynamic>.from(g as Map))).toList();
    defaults = Map<String, dynamic>.from(j['defaults'] as Map? ?? {});
    status = Map<String, dynamic>.from(j['status'] as Map? ?? {});
    notifyListeners();
  }
  Reminder draft() => Reminder(
    speechMode: 'inherit',
    speechRandom: defaults['speechRandom'] as bool? ?? false,
    speechRandomLanguage: defaults['speechRandomLanguage'] as String? ?? 'all',
    speechRandomGender: defaults['speechRandomGender'] as String? ?? 'all',
    speechRandomGroup: defaults['speechRandomGroup'] as String? ?? '',
    speechHideLocked: defaults['speechHideLocked'] as bool? ?? true,
    speechRepeat: defaults['speechRepeat'] as bool? ?? true,
    intervalMinutes: defaults['intervalMinutes'] as int? ?? 5,
    totalCount: defaults['totalCount'] as int? ?? 3,
    vibration: defaults['vibration'] as String? ?? 'three',
    sound: defaults['sound'] as bool? ?? true,
    wakeScreen: defaults['wakeScreen'] as bool? ?? true,
    ringtone: defaults['ringtone'] as String? ?? '',
    presentation: defaults['presentation'] as String? ?? 'banner',
    lockscreen: defaults['lockscreen'] as String? ?? 'private',
  );
  Future<void> saveVoiceGroups(List<VoiceGroup> groups) async {
    await native.invokeMethod('saveVoiceGroups', jsonEncode(groups.map((g) => g.toJson()).toList()));
    await load();
  }
  Future<void> save(Reminder r) async {
    await native.invokeMethod('save', jsonEncode(r.toJson()));
    unawaited(speech.preparePending());
    await load();
  }
  Future<void> ack(Reminder r) async {
    await native.invokeMethod('ack', {'id': r.id, 'token': r.activeOccurrence});
    await load();
  }
  Future<void> delete(int id) async {
    await native.invokeMethod('delete', id);
    await load();
  }
  Future<void> archive(int id) async {
    await native.invokeMethod('archive', id);
    await load();
  }
  /// Batch variants. Each native call still reschedules alarms, so this is a
  /// loop rather than one round-trip; it only avoids reloading the whole store
  /// after every single item.
  Future<void> deleteAll(Iterable<int> ids) async {
    for (final id in ids) { await native.invokeMethod('delete', id); }
    await load();
  }
  Future<void> archiveAll(Iterable<int> ids) async {
    for (final id in ids) { await native.invokeMethod('archive', id); }
    await load();
  }
  Future<void> saveDefaults() async {
    await native.invokeMethod('saveDefaults', jsonEncode(defaults));
    unawaited(speech.preparePending());
  }
  Future<void> openNotificationSettings(Reminder r) async {
    await native.invokeMethod('notificationStyleSettings', jsonEncode(r.notificationConfig));
  }
}
