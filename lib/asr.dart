import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'reminder.dart';

final asr = AsrSession();
Future<String> transcribe(String pcmPath) => asr.transcribe(pcmPath);
Future<void> discardRecording(String path) async {
  final pcm = File(path);
  if (await pcm.exists()) await pcm.delete();
}

// One model per voice session, confined to a worker isolate. No FFI pointers
// cross isolates; each utterance gets a fresh stream and reuses the model.
class AsrSession {
  final status = ValueNotifier<String>('离线模型尚未准备');
  Isolate? _worker;
  ReceivePort? _port, _errors;
  SendPort? _commands;
  Future<void>? _preparing;
  final _pending = <int, Completer<String>>{};
  Timer? _idle;
  int _serial = 0, _users = 0;
  bool _releaseRequested = false;

  Future<void> prepare() {
    _releaseRequested = false;
    _idle?.cancel();
    if (_commands != null) { _armIdle(); return Future.value(); }
    return _preparing ??= _prepare().whenComplete(() => _preparing = null);
  }
  Future<void> _prepare() async {
    try {
      status.value = '正在准备离线模型…首次使用需要稍等';
      final dir = await native.invokeMethod<String>('prepareAsr');
      if (dir == null) throw StateError('无法打开语音模型目录');
      if (_releaseRequested && _users == 0) { status.value = '离线模型已释放'; return; }
      status.value = '正在加载识别模型…';
      final ready = Completer<void>();
      final port = _port = ReceivePort();
      final errors = _errors = ReceivePort();
      port.listen((dynamic value) {
        final message = value as List;
        if (message[0] == 'ready') {
          _commands = message[1] as SendPort;
          if (!ready.isCompleted) ready.complete();
        } else if (message[0] == 'loadError') {
          if (!ready.isCompleted) ready.completeError(StateError(message[1] as String));
        } else {
          final completer = _pending.remove(message[1]);
          if (completer != null) {
            if (message[0] == 'text') { completer.complete(message[2] as String); }
            else { completer.completeError(StateError(message[2] as String)); }
          }
        }
      });
      errors.listen((dynamic error) {
        final failure = StateError('识别进程中断，请重新录音');
        if (!ready.isCompleted) ready.completeError(failure);
        for (final c in _pending.values) { if (!c.isCompleted) c.completeError(failure); }
        _pending.clear(); _close();
      });
      _worker = await Isolate.spawn(_recognizerWorker, [port.sendPort, dir], onError: errors.sendPort, errorsAreFatal: true);
      await ready.future;
      status.value = '离线模型已就绪';
      if (_releaseRequested) { release(); } else { _armIdle(); }
    } catch (_) {
      _close(); status.value = '模型准备失败，点击录音可重试'; rethrow;
    }
  }
  Future<String> transcribe(String path) async {
    _users++;
    try {
      await prepare();
      _idle?.cancel();
      status.value = '正在本地识别…';
      final result = Completer<String>();
      final id = ++_serial;
      _pending[id] = result;
      _commands!.send([id, path]);
      return await result.future;
    } finally {
      _users--;
      await discardRecording(path);
      if (_pending.isEmpty) {
        status.value = _commands == null ? '离线模型尚未准备' : '离线模型已就绪';
        if (_releaseRequested) { release(); } else { _armIdle(); }
      }
    }
  }
  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 60), release);
  }
  void release() {
    _releaseRequested = true; _idle?.cancel();
    if (_users > 0 || _pending.isNotEmpty || (_preparing != null && _commands == null)) return;
    _close(); status.value = '离线模型已释放，再次录音会自动准备';
  }
  void _close() {
    _idle?.cancel(); _commands?.send(null);
    // The worker frees its recognizer on normal shutdown. kill also bounds
    // native memory lifetime if a load or native crash failed the handshake.
    if (_commands == null) _worker?.kill(priority: Isolate.immediate);
    _worker = null; _commands = null; _port?.close(); _errors?.close();
    _port = null; _errors = null;
  }
}

void _recognizerWorker(List<dynamic> args) {
  final reply = args[0] as SendPort;
  final dir = args[1] as String;
  sherpa.OfflineRecognizer recognizer;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        paraformer: sherpa.OfflineParaformerModelConfig(model: '$dir/model.int8.onnx'),
        tokens: '$dir/tokens.txt', numThreads: 2, provider: 'cpu', modelType: 'paraformer', debug: false,
      ),
    ));
  } catch (e) { reply.send(['loadError', '$e']); return; }
  final commands = ReceivePort();
  reply.send(['ready', commands.sendPort]);
  commands.listen((dynamic request) {
    if (request == null) { recognizer.free(); commands.close(); return; }
    final id = request[0] as int;
    try {
      final bytes = File(request[1] as String).readAsBytesSync();
      if (bytes.length < 3200) throw StateError('录音太短，请说完后再结束');
      final data = ByteData.sublistView(bytes);
      final samples = Float32List(bytes.length ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
      }
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: samples, sampleRate: 16000);
        recognizer.decode(stream);
        reply.send(['text', id, recognizer.getResult(stream).text]);
      } finally { stream.free(); }
    } catch (e) { reply.send(['error', id, '$e']); }
  });
}
