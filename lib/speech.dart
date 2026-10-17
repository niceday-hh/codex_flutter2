import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'asr.dart';
import 'reminder.dart';

final speech = SpeechSession();

class SpeechSession {
  final status = ValueNotifier<String>('VITS-MNN 离线播报 · 804个音色条目');
  Future<void> _queue = Future.value();
  Future<void>? _pending;
  bool _again = false;
  int _previewTicket = 0;

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
    final ticket = ++_previewTicket;
    await native.invokeMethod('stopSpeechPreview');
    await _serial(() async {
      if (ticket != _previewTicket) return;
      final raw = await native.invokeMethod<String>('speechPreviewJob', jsonEncode(config.toJson()));
      final job = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      if (job['ready'] != true) await _generate([job]);
      if (ticket == _previewTicket) await native.invokeMethod('playSpeechPreview', job['key']);
    });
  }
  void stopPreview() { _previewTicket++; unawaited(native.invokeMethod<void>('stopSpeechPreview').catchError((Object _) {})); }

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
