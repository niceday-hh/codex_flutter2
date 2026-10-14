import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'reminder.dart';

Future<String> transcribe(String pcmPath) async {
  try {
    final dir = await native.invokeMethod<String>('filesDir');
    if (dir == null) throw StateError('无法打开语音模型目录');
    for (final name in ['model.int8.onnx', 'tokens.txt']) {
      final file = File('$dir/asr/$name');
      if (!await file.exists()) {
        await file.parent.create(recursive: true);
        final bytes = await rootBundle.load('assets/models/$name');
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
        await temp.rename(file.path);
      }
    }
    return await compute(_decode, {'dir': '$dir/asr', 'pcm': pcmPath});
  } finally {
    final pcm = File(pcmPath);
    if (await pcm.exists()) await pcm.delete();
  }
}

String _decode(Map<String, String> args) {
  sherpa.initBindings();
  final bytes = File(args['pcm']!).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final samples = Float32List(bytes.length ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  final recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      paraformer: sherpa.OfflineParaformerModelConfig(model: '${args['dir']}/model.int8.onnx'),
      tokens: '${args['dir']}/tokens.txt', numThreads: 2,
      provider: 'cpu', modelType: 'paraformer', debug: false,
    ),
  ));
  try {
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text;
    } finally { stream.free(); }
  } finally { recognizer.free(); }
}
