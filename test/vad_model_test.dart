import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
void main() {
  test('embedded pinned Silero v5 loads and does not terminate silence as a speech segment', () {
    sherpa.initBindings();
    final vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: const sherpa.SileroVadModelConfig(model: 'assets/vad/silero_vad.onnx',
          minSilenceDuration: 5, minSpeechDuration: 0.25, maxSpeechDuration: 50),
        sampleRate: 16000, numThreads: 1, debug: false),
      bufferSizeInSeconds: 60);
    try {
      for (var i = 0; i < 200; i++) { vad.acceptWaveform(Float32List(512)); }
      vad.flush();
      expect(vad.isDetected(), isFalse);
      expect(vad.isEmpty(), isTrue);
    } finally { vad.free(); }
  });
}
