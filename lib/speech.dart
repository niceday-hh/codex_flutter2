import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'asr.dart';
import 'reminder.dart';

final speech = SpeechSession();

class SpeechSession {
  final status = ValueNotifier<String>('AISHELL-3 离线播报 · 174个音色');
  Future<void> _queue = Future.value();
  Future<void>? _pending;
  bool _again = false;
  int _previewTicket = 0;

  Future<void> _serial(Future<void> Function() job) {
    final task = _queue.then((_) => asr.withoutModel(job));
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

  Future<void> _generate(List<Map<String, dynamic>> jobs) async {
    final dir = await native.invokeMethod<String>('prepareTts');
    if (dir == null) throw StateError('播报模型尚未准备');
    final events = ReceivePort();
    final finished = Completer<void>();
    final callbacks = <Future<void>>[];
    var failed = false, ended = false;
    Isolate? worker;
    events.listen((dynamic event) {
      if (event == null) {
        if (!ended && !finished.isCompleted) finished.completeError(StateError('播报进程已退出'));
        return;
      }
      final value = event as List;
      if (value.isEmpty || value[0] is! String) {
        if (!finished.isCompleted) finished.completeError(StateError('播报进程中断'));
        return;
      }
      if (value[0] == 'item') {
        failed |= value[2] != '';
        callbacks.add(native.invokeMethod<void>('speechFinished', {'key': value[1], 'error': value[2]})
          .catchError((Object _) { failed = true; }));
        status.value = value[2] == '' ? '已准备 ${value[3]}/${jobs.length} 段提醒语音' : '部分语音未就绪，将使用备用提醒';
      } else if (value[0] == 'end') {
        ended = true;
        Future.wait(callbacks).then((_) { if (!finished.isCompleted) finished.complete(); });
      } else if (!finished.isCompleted) { finished.completeError(StateError('播报工作进程异常')); }
    });
    try {
      status.value = '正在本地准备提醒语音…';
      worker = await Isolate.spawn(_speechWorker, [events.sendPort, dir, jobs], onExit: events.sendPort, onError: events.sendPort, errorsAreFatal: true);
      await finished.future;
      status.value = failed ? '部分语音未就绪，将使用备用提醒，可在设置重试' : '提醒语音已准备，到点直接播放';
    } catch (_) {
      for (final job in jobs) {
        try { await native.invokeMethod('speechFinished', {'key': job['key'], 'error': '生成未完成'}); } catch (_) {}
      }
      rethrow;
    } finally { worker?.kill(priority: Isolate.immediate); events.close(); }
  }
}

void _speechWorker(List<dynamic> request) {
  final send = request[0] as SendPort;
  final dir = request[1] as String;
  final jobs = (request[2] as List).cast<Map<String, dynamic>>();
  sherpa.OfflineTts? engine;
  try {
    sherpa.initBindings();
    engine = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(model: '$dir/model.onnx', tokens: '$dir/tokens.txt', lexicon: '$dir/lexicon.txt'),
        numThreads: 2, provider: 'cpu', debug: false),
      ruleFsts: '$dir/phone.fst,$dir/date.fst,$dir/number.fst,$dir/new_heteronym.fst',
      maxNumSenetences: 1));
    if (engine.numSpeakers != 174 || engine.sampleRate != 8000) throw StateError('播报模型元信息不匹配');
    for (var index = 0; index < jobs.length; index++) {
      final job = jobs[index];
      var error = '';
      try {
        final samples = <Float32List>[];
        var count = 0;
        final text = job['text'] as String;
        for (var offset = 0; offset < text.length; offset += 48) {
          final stop = (offset + 48).clamp(0, text.length);
          final audio = engine.generate(text: text.substring(offset, stop), sid: job['sid'] as int, speed: (job['rate'] as num).toDouble());
          if (audio.samples.isEmpty || audio.samples.any((v) => !v.isFinite)) throw StateError('未生成有效语音');
          samples.add(audio.samples); count += audio.samples.length;
          if (count > 8000 * 900) throw StateError('播报超过15分钟');
        }
        final all = Float32List(count); var offset = 0;
        for (final part in samples) { all.setRange(offset, offset + part.length, part); offset += part.length; }
        if (!sherpa.writeWave(filename: job['path'] as String, samples: all, sampleRate: 8000)) throw StateError('语音保存失败');
      } catch (_) { error = '无法生成此段语音'; final temporary = File(job['path'] as String); if (temporary.existsSync()) temporary.deleteSync(); }
      send.send(['item', job['key'], error, index + 1]);
    }
  } catch (_) {
    for (var i = 0; i < jobs.length; i++) { send.send(['item', jobs[i]['key'], '播报模型加载失败', i + 1]); }
  } finally { engine?.free(); send.send(['end']); }
}
