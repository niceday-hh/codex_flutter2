import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/asr.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/voice_flow.dart';

class LoadingAsr extends AsrSession {
  final ready = Completer<void>();
  final frames = <List<int>>[];
  final generations = <int>[];
  int detectors = 0;
  Completer<int>? firstDetector;
  List<int>? decoded;
  @override Future<void> prepare() => ready.future;
  @override Future<int> startVad(double silence, {bool Function()? isCurrent}) async {
    await prepare();
    if (isCurrent != null && !isCurrent()) return 0;
    final id = ++detectors;
    return id == 1 && firstDetector != null ? firstDetector!.future : id;
  }
  @override void feedVad(int generation, Uint8List pcm) {
    generations.add(generation); frames.add(pcm.toList());
  }
  @override Future<String> transcribe(String path, {int? maxSamples}) async {
    decoded = await File(path).readAsBytes();
    await discardRecording(path);
    return '五分钟后提醒我喝水';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('manual mic starts before cold model; buffered and live frames keep order', () async {
    final model = LoadingAsr();
    final pcm = StreamController<Uint8List>.broadcast(sync: true);
    var starts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'startRecording') starts++;
      if (call.method == 'microphoneReady') return true;
      return null;
    });
    final capture = OfflineVoiceCapture(model, pcm: pcm.stream, levels: const Stream.empty());
    await capture.open(waitForModel: false);
    await capture.start(5, (_) {}, (_) {});
    expect(starts, 1); expect(model.ready.isCompleted, isFalse);
    pcm.add(Uint8List.fromList([1, 0])); pcm.add(Uint8List.fromList([2, 0]));
    expect(capture.bufferedBytes, 4); expect(model.frames, isEmpty);
    model.ready.complete(); await Future<void>.delayed(Duration.zero);
    pcm.add(Uint8List.fromList([3, 0]));
    expect(model.frames, [[1, 0], [2, 0], [3, 0]]);
    expect(capture.bufferedBytes, 0);
    await capture.cancel(); capture.release(); model.release();
    await pcm.close(); model.status.dispose();
  });

  test('cancel during cold loading clears audio and suppresses delayed detector', () async {
    final model = LoadingAsr();
    final pcm = StreamController<Uint8List>.broadcast(sync: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async => call.method == 'microphoneReady' ? true : null);
    final capture = OfflineVoiceCapture(model, pcm: pcm.stream, levels: const Stream.empty());
    await capture.open(waitForModel: false); await capture.start(5, (_) {}, (_) {});
    pcm.add(Uint8List(3200));
    await capture.cancel(); capture.release();
    expect(capture.bufferedBytes, 0);
    model.ready.complete(); await Future<void>.delayed(Duration.zero);
    expect(model.detectors, 0); expect(model.frames, isEmpty);
    var generated = false;
    await model.withoutModel(() async { generated = true; });
    expect(generated, isTrue);
    model.release(); await pcm.close(); model.status.dispose();
  });

  test('manual stop closes mic before model readiness and preserves the complete file', () async {
    final dir = await Directory.systemTemp.createTemp('memo-capture-');
    final file = File('${dir.path}/voice.pcm'); await file.writeAsBytes([1, 0, 2, 0, 3, 0]);
    final model = LoadingAsr();
    var stopped = false, completed = false;
    DateTime? stoppedAt;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'microphoneReady') return true;
      if (call.method == 'stopRecording') { stopped = true; stoppedAt = DateTime.now(); return file.path; }
      return null;
    });
    final capture = OfflineVoiceCapture(model, pcm: const Stream.empty(), levels: const Stream.empty());
    await capture.open(waitForModel: false); await capture.start(5, (_) {}, (_) {});
    final result = capture.stop().then((v) { completed = true; return v; });
    await Future<void>.delayed(Duration.zero); expect(stopped, isTrue); expect(completed, isFalse);
    model.ready.complete();
    final voice = await result;
    expect(model.decoded, [1, 0, 2, 0, 3, 0]);
    expect(voice.reference.isAfter(stoppedAt!), isFalse);
    expect(await file.exists(), isFalse);
    capture.release(); model.release(); model.status.dispose(); await dir.delete(recursive: true);
  });

  test('cold audio cache has a hard 45-second bound and is cleared on overflow', () async {
    final model = LoadingAsr();
    final pcm = StreamController<Uint8List>.broadcast(sync: true);
    final endpoints = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async => call.method == 'microphoneReady' ? true : null);
    final capture = OfflineVoiceCapture(model, pcm: pcm.stream, levels: const Stream.empty());
    await capture.open(waitForModel: false); await capture.start(5, endpoints.add, (_) {});
    for (var i = 0; i < 450; i++) { pcm.add(Uint8List(3200)); }
    expect(capture.bufferedBytes, OfflineVoiceCapture.maxBufferedBytes);
    expect(endpoints, isEmpty);
    pcm.add(Uint8List(2)); expect(endpoints, [-1]); expect(capture.bufferedBytes, 0);
    await capture.cancel(); capture.release(); model.ready.complete(); await Future<void>.delayed(Duration.zero);
    expect(model.frames, isEmpty);
    model.release(); await pcm.close(); model.status.dispose();
  });

  test('late VAD initialization from a previous recording cannot feed the next one', () async {
    final model = LoadingAsr()..firstDetector = Completer<int>();
    model.ready.complete();
    final pcm = StreamController<Uint8List>.broadcast(sync: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async => call.method == 'microphoneReady' ? true : null);
    final capture = OfflineVoiceCapture(model, pcm: pcm.stream, levels: const Stream.empty());
    await capture.open(); await capture.start(5, (_) {}, (_) {}); await Future<void>.delayed(Duration.zero);
    pcm.add(Uint8List.fromList([1, 0]));
    await capture.cancel(); await capture.start(5, (_) {}, (_) {}); await Future<void>.delayed(Duration.zero);
    pcm.add(Uint8List.fromList([2, 0]));
    model.firstDetector!.complete(1); await Future<void>.delayed(Duration.zero);
    pcm.add(Uint8List.fromList([3, 0]));
    expect(model.frames, [[2, 0], [3, 0]]); expect(model.generations, [2, 2]);
    await capture.cancel(); capture.release(); model.release(); await pcm.close(); model.status.dispose();
  });

  test('cold model failure reports once and does not leak an unhandled future', () async {
    final model = LoadingAsr();
    final endpoints = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async => call.method == 'microphoneReady' ? true : null);
    final capture = OfflineVoiceCapture(model, pcm: const Stream.empty(), levels: const Stream.empty());
    await capture.open(waitForModel: false); await capture.start(5, endpoints.add, (_) {});
    model.ready.completeError(StateError('fixture load failure')); await Future<void>.delayed(Duration.zero);
    expect(endpoints, [-1]); expect(capture.bufferedBytes, 0);
    await capture.cancel(); capture.release(); model.release(); model.status.dispose();
  });
}
