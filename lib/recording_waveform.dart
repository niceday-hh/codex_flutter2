import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// A bounded RMS-amplitude history, updated by the existing PCM recorder at 10 Hz.
class RecordingMeter extends ChangeNotifier {
  final List<double> levels = List.filled(33, 0);
  bool active = false;
  double level = 0, dbfs = -90, peak = 0;
  void start() { active = true; _clear(); notifyListeners(); }
  void stop() { active = false; _clear(); notifyListeners(); }
  void _clear() { levels.fillRange(0, levels.length, 0); level = 0; dbfs = -90; peak = 0; }
  void accept(dynamic event) {
    if (!active || event is! Map) return;
    final rms = event['dbfs'], top = event['peak'];
    if (rms is! num || top is! num || !rms.isFinite || !top.isFinite) return;
    dbfs = rms.toDouble().clamp(-90.0, 0.0).toDouble(); peak = top.toDouble().clamp(0.0, 1.0).toDouble();
    final target = ((dbfs + 60) / 60).clamp(0.0, 1.0);
    level = target > level ? 0.7 * target + 0.3 * level : 0.35 * target + 0.65 * level;
    for (var i = 0; i < levels.length - 1; i++) { levels[i] = levels[i + 1]; }
    levels[levels.length - 1] = level;
    notifyListeners();
  }
  String get description => !active ? '波形显示实际录音音量' : peak >= 0.97 ? '音量接近满幅，请稍离远一点'
    : dbfs < -45 ? '声音偏小，请靠近麦克风' : dbfs > -15 ? '声音较大' : '收音适中';
}

class RecordingWaveform extends StatelessWidget {
  final RecordingMeter meter;
  const RecordingWaveform({super.key, required this.meter});
  @override Widget build(BuildContext context) => Column(children: [
    RepaintBoundary(child: SizedBox(height: 38, width: double.infinity,
      child: CustomPaint(painter: RecordingWavePainter(meter, context.colors.brand500)))),
    const SizedBox(height: 8), AnimatedBuilder(animation: meter, builder: (_, child) =>
      Text(meter.description, style:  TextStyle(color: context.colors.muted, fontSize: 12))),
  ]);
}

class RecordingWavePainter extends CustomPainter {
  final RecordingMeter meter;
  final Color color;
  RecordingWavePainter(this.meter, this.color) : super(repaint: meter);
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: meter.active ? 0.8 : 0.25)
      ..strokeWidth = 3..strokeCap = StrokeCap.round;
    final step = (size.width / meter.levels.length).clamp(0.0, 7.0);
    for (var i = 0; i < meter.levels.length; i++) {
      final x = size.width / 2 + (i - 16) * step;
      final height = 1.5 + meter.levels[i] * 16;
      canvas.drawLine(Offset(x, size.height / 2 - height), Offset(x, size.height / 2 + height), paint);
    }
  }
  @override bool shouldRepaint(RecordingWavePainter oldDelegate) => oldDelegate.meter != meter;
}
