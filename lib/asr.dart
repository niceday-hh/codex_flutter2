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
  int _serial = 0, _users = 0, _pins = 0, _vadGeneration = 0;
  Completer<void>? _unpinned;
  final vadEvents = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  Future<void> retainVoice() async {
    while (_suspension != null) { await _suspension; }
    _pins++; _idle?.cancel();
    try { await prepare(); } catch (_) { releaseVoice(); rethrow; }
  }
  void releaseVoice() {
    if (_pins == 0) return;
    _pins--;
    if (_pins == 0) {
      _unpinned?.complete(); _unpinned = null;
      release();
    }
  }
  Future<int> startVad(double silence) async {
    await prepare();
    final id = ++_vadGeneration;
    final ready = Completer<String>();
    final request = ++_serial; _pending[request] = ready;
    _commands!.send(['vadStart', request, id, silence]);
    await ready.future;
    return id;
  }
  void feedVad(int generation, Uint8List pcm) {
    if (generation != _vadGeneration || _commands == null) return;
    _commands!.send(['pcm', generation, TransferableTypedData.fromList([pcm])]);
  }
  void stopVad() { _vadGeneration++; _commands?.send(['vadStop']); }

  bool _releaseRequested = false;
  Future<void>? _suspension;
  Completer<void>? _drained, _closed;

  Future<T> withoutModel<T>(Future<T> Function() work) async {
    while (_pins > 0) { _unpinned ??= Completer<void>(); await _unpinned!.future; }
    final previous = _suspension;
    final paused = Completer<void>();
    _suspension = paused.future;
    try {
      if (previous != null) await previous;
      release();
      if (_preparing != null) await _preparing!.catchError((Object _) {});
      if (_users > 0) { _drained ??= Completer<void>(); await _drained!.future; }
      release();
      if (_closed != null) await _closed!.future;
      return await work();
    } finally {
      paused.complete();
      if (identical(_suspension, paused.future)) _suspension = null;
    }
  }


  Future<void> prepare() async {
    if (_suspension != null) await _suspension;
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
      final vadPath = await native.invokeMethod<String>('prepareVad');
      if (vadPath == null) throw StateError('无法打开人声检测模型');
      if (_releaseRequested && _users == 0 && _pins == 0) { status.value = '离线模型已释放'; return; }
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
        } else if (message[0] == 'vad') {
          vadEvents.add(Map<String, dynamic>.from(message[1] as Map));
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
      final exited = ReceivePort();
      final closed = _closed = Completer<void>();
      exited.listen((_) { if (!closed.isCompleted) closed.complete(); exited.close(); });
      _worker = await Isolate.spawn(_recognizerWorker, [port.sendPort, dir, vadPath], onError: errors.sendPort, onExit: exited.sendPort, errorsAreFatal: true);
      await ready.future;
      status.value = '离线模型已就绪';
      if (_releaseRequested) { release(); } else { _armIdle(); }
    } catch (_) {
      if (_worker == null && _closed != null && !_closed!.isCompleted) _closed!.complete();
      _close(); status.value = '模型准备失败，点击录音可重试'; rethrow;
    }
  }
  Future<String> transcribe(String path, {int? maxSamples}) async {
    if (_suspension != null) await _suspension;
    _users++;
    try {
      await prepare();
      _idle?.cancel();
      status.value = '正在本地识别…';
      final result = Completer<String>();
      final id = ++_serial;
      _pending[id] = result;
      _commands!.send([id, path, maxSamples]);
      return await result.future;
    } finally {
      _users--;
      if (_users == 0 && _drained != null) { _drained!.complete(); _drained = null; }
      await discardRecording(path);
      if (_pending.isEmpty) {
        status.value = _commands == null ? '离线模型尚未准备' : '离线模型已就绪';
        if (_releaseRequested) { release(); } else { _armIdle(); }
      }
    }
  }
  void _armIdle() {
    _idle?.cancel();
    if (_pins == 0) _idle = Timer(const Duration(seconds: 60), release);
  }
  void release() {
    _releaseRequested = true; _idle?.cancel();
    if (_pins > 0 || _users > 0 || _pending.isNotEmpty || (_preparing != null && _commands == null)) return;
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
  sherpa.VoiceActivityDetector? vad;
  var vadGeneration = 0;
  var speechSeen = false;
  var reported = false;
  final commands = ReceivePort();
  reply.send(['ready', commands.sendPort]);
  commands.listen((dynamic request) {
    if (request == null) { vad?.free(); recognizer.free(); commands.close(); return; }
    if (request[0] == 'vadStop') { vad?.free(); vad = null; return; }
    if (request[0] == 'vadStart') {
      final id = request[1] as int;
      try {
        vad?.free(); vad = null;
        vadGeneration = request[2] as int; speechSeen = false; reported = false;
        vad = sherpa.VoiceActivityDetector(config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(model: args[2] as String,
            minSilenceDuration: (request[3] as num).toDouble(), minSpeechDuration: 0.25,
            maxSpeechDuration: 50),
          sampleRate: 16000, numThreads: 1, provider: 'cpu', debug: false),
          bufferSizeInSeconds: 60);
        reply.send(['text', id, 'ready']);
      } catch (e) { reply.send(['error', id, '$e']); }
      return;
    }
    if (request[0] == 'pcm') {
      if (vad == null || request[1] != vadGeneration || reported) return;
      try {
        final bytes = (request[2] as TransferableTypedData).materialize().asUint8List();
        final data = ByteData.sublistView(bytes);
        final samples = Float32List(bytes.length ~/ 2);
        for (var i = 0; i < samples.length; i++) { samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0; }
        vad!.acceptWaveform(samples);
        if (vad!.isDetected() && !speechSeen) {
          speechSeen = true;
          reply.send(['vad', {'generation': vadGeneration, 'speech': true}]);
        }
        if (!vad!.isEmpty()) {
          final segment = vad!.front(); reported = true;
          reply.send(['vad', {'generation': vadGeneration, 'endSample': segment.start + segment.samples.length}]);
          vad!.pop();
        }
      } catch (e) {
        reported = true;
        reply.send(['vad', {'generation': vadGeneration, 'error': '$e'}]);
      }
      return;
    }
    final id = request[0] as int;
    try {
      final bytes = File(request[1] as String).readAsBytesSync();
      if (bytes.length < 3200) throw StateError('录音太短，请说完后再结束');
      final data = ByteData.sublistView(bytes);
      final limit = request.length > 2 && request[2] is int ? request[2] as int : bytes.length ~/ 2;
      final sampleCount = limit.clamp(0, bytes.length ~/ 2).toInt();
      final samples = Float32List(sampleCount);
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
