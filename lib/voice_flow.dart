import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'asr.dart';
import 'recording_waveform.dart';
import 'reminder.dart';
import 'app_error.dart';
import 'voice_parser.dart';

enum VoicePhase { idle, preparing, commands, recording, processing, confirming, saving }

class CapturedVoice {
  final String text;
  final DateTime reference;
  const CapturedVoice(this.text, this.reference);
}

abstract class VoiceCapture {
  Future<void> open();
  Future<void> start(double silence, void Function(int endSample) endpoint, void Function(Object) level);
  Future<CapturedVoice> stop({int? endSample});
  Future<void> cancel();
  void release();
}

class OfflineVoiceCapture implements VoiceCapture {
  final AsrSession session;
  OfflineVoiceCapture(this.session);
  StreamSubscription<dynamic>? _pcm, _levels;
  StreamSubscription<Map<String, dynamic>>? _vad;
  bool _retained = false, _accepting = false;
  DateTime _started = DateTime.now();
  int _generation = 0;
  @override Future<void> open() async {
    if (_retained) return;
    await session.retainVoice(); _retained = true;
  }
  @override Future<void> start(double silence, void Function(int) endpoint, void Function(Object) level) async {
    await _unsubscribe();
    _generation = await session.startVad(silence);
    final generation = _generation;
    _vad = session.vadEvents.stream.listen((event) {
      if (!_accepting || event['generation'] != generation) return;
      if (event['error'] != null) { _accepting = false; endpoint(-1); }
      else if (event['endSample'] is int) { endpoint(event['endSample'] as int); }
    });
    _pcm = const EventChannel('memo/recordingPcm').receiveBroadcastStream().listen((dynamic data) {
      if (_accepting && data is Uint8List) session.feedVad(generation, data);
    }, onError: (Object _) { if (_accepting) { _accepting = false; endpoint(-1); } });
    _levels = const EventChannel('memo/recordingLevels').receiveBroadcastStream().listen(
      (dynamic value) { if (_accepting && value != null) level(value as Object); },
      onError: (Object _) {});
    _accepting = true; _started = DateTime.now();
    await native.invokeMethod<void>('startRecording');
    _started = DateTime.now();
    // A visible assistant can silence an otherwise successfully started recorder.
    for (var i = 0; i < 40; i++) {
      if (!_accepting) return;
      if (await native.invokeMethod<bool>('microphoneReady') == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('麦克风暂不可用，请先关闭 YOYO 面板或其它录音应用后重试');
  }
  Future<void> _unsubscribe() async {
    _accepting = false; session.stopVad();
    final pcm = _pcm, levels = _levels, vad = _vad;
    _pcm = null; _levels = null; _vad = null;
    await pcm?.cancel(); await levels?.cancel(); await vad?.cancel();
  }
  @override Future<CapturedVoice> stop({int? endSample}) async {
    final ended = DateTime.now();
    await _unsubscribe();
    final path = await native.invokeMethod<String>('stopRecording');
    if (path == null) throw StateError('没有录音，请重试');
    final reference = endSample != null && endSample > 0
      ? _started.add(Duration(microseconds: (endSample * 1000000 / 16000).round())) : ended;
    final text = await session.transcribe(path, maxSamples: endSample);
    return CapturedVoice(text, reference.isAfter(ended) ? ended : reference);
  }
  @override Future<void> cancel() async {
    await _unsubscribe();
    await native.invokeMethod<void>('cancelRecording');
  }
  @override void release() {
    if (_retained) { _retained = false; session.releaseVoice(); }
  }
}

String commandText(String text) => text.replaceAll(RegExp(r'[\s，。！？、；：,.!?;:]'), '');
bool isVoiceConfirm(String text) => const {'确认', '确认创建', '确认保存', '确定', '确定创建', '保存提醒'}.contains(commandText(text));
bool isVoiceAgain(String text) => const {'重新录音', '重新录', '重录', '再录一次'}.contains(commandText(text));
bool isVoiceCancel(String text) => const {'取消', '取消创建', '取消录音', '退出', '退出录音'}.contains(commandText(text));

/// Owns one foreground interaction. Epoch checks discard late native/ASR replies.
/// No TTS call is made by this class, including at confirmation.
class VoiceFlow extends ChangeNotifier {
  final VoiceCapture capture;
  final MemoStore store;
  final VoidCallback openVoicePage;
  final Future<void> Function() onSaved;
  final DateTime Function() now;
  final meter = RecordingMeter();
  VoicePhase phase = VoicePhase.idle;
  ParsedVoice? pending;
  String text = '', message = '';
  DateTime? reference;
  int secondsLeft = 0, elapsed = 0;
  int _epoch = 0;
  VoicePhase _captureMode = VoicePhase.idle;
  bool _disposed = false;
  Timer? _limit, _ticker;
  DateTime? _confirmDeadline, _commandDeadline;
  Future<void> _tail = Future.value();
  VoiceFlow({required this.capture, required this.store, required this.openVoicePage,
    required this.onSaved, DateTime Function()? clock}) : now = clock ?? DateTime.now;
  bool get capturing => phase == VoicePhase.commands || phase == VoicePhase.recording || phase == VoicePhase.confirming;
  bool get busy => phase == VoicePhase.preparing || phase == VoicePhase.processing || phase == VoicePhase.saving;
  bool get active => phase != VoicePhase.idle;
  void _notify() { if (!_disposed) notifyListeners(); }
  Future<void> _queue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((Object _) {});
    return next;
  }
  bool _current(int ticket) => !_disposed && ticket == _epoch;
  void _stopTimers() { _limit?.cancel(); _ticker?.cancel(); meter.stop(); }
  void _countdown(Duration duration, VoidCallback expired) {
    _limit?.cancel(); _ticker?.cancel();
    secondsLeft = duration.inSeconds; elapsed = 0;
    _limit = Timer(duration, expired);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed++; if (secondsLeft > 0) secondsLeft--; _notify();
    });
  }
  Future<void> startCommands() => _start(VoicePhase.commands);
  Future<void> startRecording() => _start(VoicePhase.recording);
  Future<void> _start(VoicePhase mode) {
    final ticket = ++_epoch;
    _stopTimers(); pending = null; _confirmDeadline = null; _commandDeadline = null;
    phase = VoicePhase.preparing; message = '正在准备麦克风和离线模型…'; _notify();
    return _queue(() async {
      try {
        await capture.cancel();
        if (!_current(ticket)) return;
        await capture.open();
        if (!_current(ticket)) return;
        if (mode == VoicePhase.recording) { text = ''; reference = null; openVoicePage(); }
        await _listen(mode, ticket);
      } catch (e) { await _failure(e, ticket); }
    });
  }
  Future<void> _listen(VoicePhase mode, int ticket) async {
    if (!_current(ticket)) return;
    final silence = mode == VoicePhase.recording ? (store.defaults['voiceSilenceSeconds'] as num? ?? 5).toDouble() : 0.7;
    phase = VoicePhase.preparing; message = '正在准备聆听…'; _notify();
    _captureMode = mode;
    await capture.start(silence, (end) {
      if (!_current(ticket)) return;
      if (end < 0) { unawaited(_failure(StateError('人声检测中断，请重试或使用手动录音'), ticket)); return; }
      if (mode == VoicePhase.recording && store.defaults['voiceAutoStop'] == false) return;
      unawaited(finish(endSample: end));
    }, meter.accept);
    if (!_current(ticket)) return;
    phase = mode; meter.start();
    if (mode == VoicePhase.commands) _commandDeadline ??= now().add(const Duration(seconds: 15));
    message = switch (mode) {
      VoicePhase.commands => '正在预听，可说“开始录音”',
      VoicePhase.confirming => '请说“确认”“重新录音”或“取消”',
      _ => '正在录音；连续安静后自动识别',
    };
    final duration = mode == VoicePhase.recording ? const Duration(seconds: 45)
      : mode == VoicePhase.commands ? _commandDeadline!.difference(now())
      : (_confirmDeadline ?? now().add(const Duration(seconds: 20))).difference(now());
    if (duration <= Duration.zero) { await _closeInside(pending == null ? '预听已结束，麦克风已关闭' : '确认超时，草稿已保留，可用下方按钮继续'); return; }
    _countdown(duration, () {
      if (!_current(ticket)) return;
      if (mode == VoicePhase.recording) { unawaited(finish()); }
      else { unawaited(pause(keepDraft: pending != null, notice: pending == null ? '预听已结束，麦克风已关闭' : '确认超时，草稿已保留，可用下方按钮继续')); }
    });
    _notify();
  }
  Future<void> finish({int? endSample}) {
    if (!capturing && phase != VoicePhase.preparing) return Future.value();
    final mode = pending != null ? VoicePhase.confirming : _captureMode;
    final ticket = _epoch;
    _stopTimers(); phase = VoicePhase.processing; message = '正在本地识别…'; _notify();
    return _queue(() async {
      try {
        final result = await capture.stop(endSample: endSample);
        if (!_current(ticket)) return;
        final utterance = result.text.trim();
        if (mode == VoicePhase.commands) {
          if (isVoiceCancel(utterance)) { await _closeInside('预听已取消'); return; }
          final start = RegExp(r'^\s*(?:请)?(?:开始录音|打开录音|切换到录音(?:页面|页)?)[，,。；;\s]*').firstMatch(utterance);
          if (start == null) {
            await _listen(VoicePhase.commands, ticket);
            return;
          }
          openVoicePage();
          final remainder = utterance.substring(start.end).trim();
          if (remainder.isNotEmpty) {
            text = remainder; reference = result.reference;
            await _prepareConfirmation(ticket);
          } else { text = ''; reference = null; await _listen(VoicePhase.recording, ticket); }
        } else if (mode == VoicePhase.confirming) {
          if (isVoiceConfirm(utterance)) { await _saveInside(ticket); }
          else if (isVoiceAgain(utterance)) {
            pending = null; text = ''; reference = null; _confirmDeadline = null;
            await _listen(VoicePhase.recording, ticket);
          } else if (isVoiceCancel(utterance)) { pending = null; await _closeInside('已取消创建'); }
          else { message = '请说“确认”“重新录音”或“取消”'; await _listen(VoicePhase.confirming, ticket); }
        } else {
          text = utterance; reference = result.reference;
          if (utterance.isEmpty) { await _closeInside('没有听清，请重新录音'); return; }
          await _prepareConfirmation(ticket);
        }
      } catch (e) { await _failure(e, ticket); }
    });
  }
  Future<void> reviewText(String value) {
    if (busy || capturing) return Future.value();
    final ticket = ++_epoch;
    text = value.trim(); reference ??= now();
    return _queue(() async {
      try { await capture.open(); if (_current(ticket)) await _prepareConfirmation(ticket); }
      catch (e) { await _failure(e, ticket); }
    });
  }
  Future<void> _prepareConfirmation(int ticket) async {
    pending = parseVoice(text, now: reference ?? now(), defaults: store.draft());
    _confirmDeadline = now().add(const Duration(seconds: 20));
    phase = VoicePhase.preparing; message = '请核对日期、时间和内容'; _notify();
    await _listen(VoicePhase.confirming, ticket);
  }
  String? get validationError {
    final parsed = pending;
    if (parsed == null) return '没有待确认的需求';
    final r = parsed.reminder;
    if (r.text.trim().isEmpty) return '没有提醒正文，请重新录音';
    if (!parsed.hasTime || !r.timeConfirmed || !r.dateConfirmed) return '日期或时间不完整，请重新录音或手动编辑';
    if (parsed.warning != null) return parsed.warning;
    if (r.repeat == 'none' && !r.date.isAfter(now())) return '这个时间已过去，请重新录音或手动调整';
    return null;
  }
  Future<void> confirm() {
    if (pending == null || phase == VoicePhase.saving) return Future.value();
    final ticket = _epoch;
    _stopTimers(); phase = VoicePhase.saving; _notify();
    return _queue(() => _saveInside(ticket));
  }
  Future<void> _saveInside(int ticket) async {
    if (!_current(ticket) || pending == null) return;
    final error = validationError;
    if (error != null) {
      await capture.cancel(); capture.release();
      phase = VoicePhase.idle; message = error; _notify(); return;
    }
    _stopTimers(); phase = VoicePhase.saving; message = '正在保存提醒…'; _notify();
    await capture.cancel(); capture.release();
    if (!_current(ticket)) return;
    final draft = pending!.reminder;
    try {
      await store.save(draft);
      // The save itself has completed: never retry it automatically on UI reload failure.
      pending = null; phase = VoicePhase.idle; message = '提醒已创建';
      _confirmDeadline = null; _notify();
      try { await onSaved(); } catch (_) {}
    } catch (e) {
      if (_current(ticket)) { phase = VoicePhase.idle; message = niceError(e); _notify(); }
    }
  }
  Future<void> pause({bool keepDraft = true, String notice = '聆听已暂停，麦克风已关闭'}) {
    ++_epoch; _stopTimers(); phase = VoicePhase.idle; message = notice;
    if (!keepDraft) pending = null;
    _notify();
    return _queue(() async { try { await capture.cancel(); } finally { capture.release(); } });
  }
  Future<void> cancel() => pause(keepDraft: false, notice: '已取消，麦克风已关闭');
  Future<void> _closeInside(String notice) async {
    _stopTimers(); await capture.cancel(); capture.release();
    phase = VoicePhase.idle; message = notice; _notify();
  }
  Future<void> _failure(Object error, int ticket) async {
    if (!_current(ticket)) return;
    await _closeInside(niceError(error));
  }
  @override void dispose() {
    _disposed = true; ++_epoch; _stopTimers();
    unawaited(_queue(() async { try { await capture.cancel(); } finally { capture.release(); } }));
    meter.dispose(); super.dispose();
  }
}
