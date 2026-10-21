import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'asr.dart';
import 'reminder.dart';

final speech = SpeechSession();

class SpeechPreviewState {
  final Object? owner;
  final int? reminderId;
  final bool playing;
  final String? error;
  const SpeechPreviewState({this.owner, this.reminderId, this.playing = false, this.error});
}

class SpeechSession {
  final status = ValueNotifier<String>('VITS-MNN 离线播报 · 804个音色条目');
  Future<void> _queue = Future.value();
  Future<void>? _pending;
  bool _again = false;
  int _previewTicket = 0;
  final previewState = ValueNotifier<SpeechPreviewState>(const SpeechPreviewState());
  int _beginPreview({Object? owner, int? reminderId}) {
    final ticket = ++_previewTicket;
    previewState.value = SpeechPreviewState(owner: owner, reminderId: reminderId);
    return ticket;
  }
  void previewEnded(int ticket, {String? error}) {
    if (ticket != _previewTicket) return;
    final previous = previewState.value;
    previewState.value = SpeechPreviewState(owner: previous.owner, reminderId: previous.reminderId, error: error ?? previous.error);
  }

  Future<void> _serial(Future<void> Function() job) {
    final task = _queue.then((_) => job());
    _queue = task.catchError((Object _) {});
    return task;
  }
  Future<void> preparePending({bool retry = false}) {
    if (_pending != null) { _again = true; return _pending!; }
    return _pending = _serial(() async {
      do {
        _again = false;
        final raw = await native.invokeMethod<String>('speechJobs', retry);
        final jobs = (jsonDecode(raw ?? '[]') as List).cast<Map<String, dynamic>>();
        if (jobs.isNotEmpty) await _generate(jobs);
      } while (_again);
    }).catchError((Object e) { status.value = '语音准备暂未完成，提醒仍有效，可在设置重试'; })
      .whenComplete(() => _pending = null);
  }
  Future<void> preview(Reminder config) async {
    final ticket = _beginPreview();
    await native.invokeMethod('stopSpeechPreview');
    await _serial(() async {
      if (ticket != _previewTicket) return;
      final raw = await native.invokeMethod<String>('speechPreviewJob', jsonEncode(config.toJson()));
      final job = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      if (job['ready'] != true) await _generate([job]);
      await _play(job['key'] as String, ticket);
    });
  }
  Future<bool> _play(String key, int ticket) async {
    if (ticket != _previewTicket) return false;
    final started = await native.invokeMethod<bool>('playSpeechPreview', {'key': key, 'token': ticket});
    if (started == false || ticket != _previewTicket) return false;
    final current = previewState.value;
    previewState.value = SpeechPreviewState(owner: current.owner, reminderId: current.reminderId, playing: true);
    return true;
  }
  Future<T> withReminderAudio<T>(int id, Future<T> Function(Map<String, dynamic> job) use) async {
    final raw = await native.invokeMethod<String>('reminderAudioJob', id);
    if (raw == null) throw StateError('无法读取这条提醒的音频设置');
    final job = jsonDecode(raw) as Map<String, dynamic>;
    final lease = job['lease'] as String;
    try {
      if (job['ready'] != true) {
        await _serial(() async {
          if (await native.invokeMethod<bool>('reminderAudioReady', lease) != true) await _generate([job]);
        });
      }
      if (await native.invokeMethod<bool>('reminderAudioReady', lease) != true) throw StateError('这条提醒的音频尚未准备完成，请重试');
      return await use(job);
    } finally {
      try { await native.invokeMethod('releaseReminderAudio', lease); } catch (_) {}
    }
  }
  Future<void> releaseAudio(Map<String, dynamic> job) async {
    try { await native.invokeMethod('releaseReminderAudio', job['lease']); } catch (_) {}
  }
  Future<Map<String, dynamic>> prepareCandidate(int id) async {
    final raw = await native.invokeMethod<String>('candidateReminderAudio', id);
    if (raw == null) throw StateError('无法准备新版本');
    final job = jsonDecode(raw) as Map<String, dynamic>;
    try {
      await _serial(() async {
        if (await native.invokeMethod<bool>('reminderAudioReady', job['lease']) != true) {
          final companions = (job['companions'] as List? ?? []).cast<Map<String, dynamic>>();
          await _generate([...companions.where((j) => j['ready'] != true), if (job['ready'] != true) job]);
        }
      });
      if (await native.invokeMethod<bool>('reminderAudioReady', job['lease']) != true) throw StateError('新版本生成未完成，请重试');
      return job;
    } catch (_) { await releaseAudio(job); rethrow; }
  }
  Future<bool> previewCandidate(Map<String, dynamic> job, {required Object owner}) async {
    final ticket = _beginPreview(owner: owner, reminderId: job['reminderId'] as int?);
    await native.invokeMethod('stopSpeechPreview');
    return _play(job['key'] as String, ticket);
  }
  Future<void> useCandidate(Map<String, dynamic> job) async {
    if (await native.invokeMethod<bool>('selectReminderAudio', job['lease']) != true) throw StateError('无法保存音频版本');
  }
  Future<bool> previewReminder(int id, {required Object owner}) async {
    final ticket = _beginPreview(owner: owner, reminderId: id);
    await native.invokeMethod('stopSpeechPreview');
    if (ticket != _previewTicket) return false;
    return withReminderAudio(id, (job) => _play(job['key'] as String, ticket));
  }
  void stopPreview({Object? owner}) {
    if (owner != null && !identical(owner, previewState.value.owner)) return;
    _previewTicket++; previewState.value = const SpeechPreviewState();
    unawaited(native.invokeMethod<void>('stopSpeechPreview').catchError((Object _) {}));
  }

  Future<void> _generate(List<Map<String, dynamic>> jobs) => asr.withoutModel(() => _generateIsolated(jobs));

  Future<void> _generateIsolated(List<Map<String, dynamic>> jobs) async {
    var failed = false;
    try {
      status.value = '正在本地准备提醒语音…';
      await native.invokeMethod<String>('prepareTts');
      for (var i = 0; i < jobs.length; i++) {
        final job = jobs[i];
        var failure = '';
        try { await native.invokeMethod('generateSpeech', jsonEncode(job)); }
        catch (_) { failure = '生成未完成'; failed = true; }
        await native.invokeMethod('speechFinished', {'key': job['key'], 'error': failure});
        status.value = failure.isEmpty ? '已准备 ${i + 1}/${jobs.length} 段提醒语音' : '部分语音未就绪，将使用备用提醒';
      }
      status.value = failed ? '部分语音未就绪，将使用备用提醒，可在设置重试' : '提醒语音已准备，到点直接播放';
    } catch (_) {
      for (final job in jobs) {
        try { await native.invokeMethod('speechFinished', {'key': job['key'], 'error': '生成未完成'}); } catch (_) {}
      }
      rethrow;
    } finally { await native.invokeMethod('closeTts'); }
  }
}
