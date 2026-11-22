import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// A bounded RMS-amplitude history, updated by the existing PCM recorder at 10 Hz.
class RecordingMeter extends ChangeNotifier {
  final List<double> levels = List.filled(33, 0);
  bool active = false;
  double level = 0, dbfs = -90, peak = 0;

  void start() {
    active = true;
    _clear();
    notifyListeners();
  }

  void stop() {
    active = false;
    _clear();
    notifyListeners();
  }

  void _clear() {
    levels.fillRange(0, levels.length, 0);
    level = 0;
    dbfs = -90;
    peak = 0;
  }

  void accept(dynamic event) {
    if (!active || event is! Map) return;
    final rms = event['dbfs'], top = event['peak'];
    if (rms is! num || top is! num || !rms.isFinite || !top.isFinite) return;
    dbfs = rms.toDouble().clamp(-90.0, 0.0).toDouble();
    peak = top.toDouble().clamp(0.0, 1.0).toDouble();
    final target = ((dbfs + 60) / 60).clamp(0.0, 1.0);
    level = target > level ? 0.7 * target + 0.3 * level : 0.35 * target + 0.65 * level;
    for (var i = 0; i < levels.length - 1; i++) {
      levels[i] = levels[i + 1];
    }
    levels[levels.length - 1] = level;
    notifyListeners();
  }

  String get description => !active
      ? '波形显示实际录音音量'
      : peak >= 0.97
          ? '音量接近满幅，请稍离远一点'
          : dbfs < -45
              ? '声音偏小，请靠近麦克风'
              : dbfs > -15
                  ? '声音较大'
                  : '收音适中';
}

class RecordingWaveform extends StatelessWidget {
  final RecordingMeter meter;
  const RecordingWaveform({super.key, required this.meter});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final auraPrimary = dark ? const Color(0xFF5EEAD4) : c.brand400;
    final auraSecondary = c.brand500;

    return Column(children: [
      const SizedBox(height: 12),
      Container(
        height: 82,
        width: double.infinity,
        decoration: BoxDecoration(
          color: dark
              ? c.surfaceAlt.withValues(alpha: 0.72)
              : c.brand50.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(MemoRadius.xl),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.09)
                : c.line.withValues(alpha: 0.8),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Static ambient aura inside RepaintBoundary: zero ticker, zero blur cost.
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.28, 0),
                        radius: 1.05,
                        colors: [
                          auraPrimary.withValues(alpha: dark ? 0.18 : 0.10),
                          auraSecondary.withValues(alpha: dark ? 0.14 : 0.06),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.52, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.36, 0),
                        radius: 0.95,
                        colors: [
                          auraSecondary.withValues(alpha: dark ? 0.22 : 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            RepaintBoundary(
              child: SizedBox(
                height: 68,
                width: double.infinity,
                child: CustomPaint(
                  painter: RecordingWavePainter(
                    meter,
                    c.brand500,
                    lowColor: dark ? const Color(0xFF5EEAD4) : c.brand200,
                    peakColor: c.danger,
                    dark: dark,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      AnimatedBuilder(
        animation: meter,
        builder: (_, child) => Text(
          meter.description,
          style: TextStyle(
            color: meter.active && meter.peak >= 0.97 ? c.danger : c.muted,
            fontSize: 12,
          ),
        ),
      ),
    ]);
  }
}

class RecordingWavePainter extends CustomPainter {
  final RecordingMeter meter;
  final Color color;
  final Color? lowColor;
  final Color? peakColor;
  final bool dark;

  RecordingWavePainter(
    this.meter,
    this.color, {
    this.lowColor,
    this.peakColor,
    this.dark = false,
  }) : super(repaint: meter);

  @override
  void paint(Canvas canvas, Size size) {
    final count = meter.levels.length;
    final half = (count - 1) / 2.0;
    final step = ((size.width - 28) / count).clamp(0.0, 7.6);
    final edgeTone = lowColor ?? color.withValues(alpha: 0.45);
    final clipping = meter.active && meter.peak >= 0.97;
    final corePaint = Paint()..strokeCap = StrokeCap.round;
    final glowPaint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final normPos = i / (count - 1); // 0 left -> 1 right
      final normDist = (i - half).abs() / half; // 0 center -> 1 edge
      final envelope = 0.36 + 0.64 * math.cos(normDist * math.pi * 0.5);
      final amp = meter.levels[i];
      final x = size.width / 2 + (i - half) * step;
      final maxHalfHeight = (size.height / 2) - 4;
      final height = (2.2 + amp * (maxHalfHeight - 2.2) * (0.64 + 0.36 * envelope))
          .clamp(2.0, maxHalfHeight);

      // Luminous left-to-right gradient in dark mode (cyan-teal -> brand violet).
      final baseTone = dark
          ? Color.lerp(edgeTone, color, normPos)!
          : Color.lerp(edgeTone, color, (0.35 + 0.65 * amp).clamp(0.0, 1.0))!;
      final barColor = clipping && amp > 0.72 && peakColor != null
          ? Color.lerp(baseTone, peakColor, ((amp - 0.72) / 0.28).clamp(0.0, 1.0))!
          : baseTone;

      final alpha = meter.active
          ? (0.30 + 0.68 * envelope * (0.50 + 0.50 * amp)).clamp(0.0, 1.0)
          : 0.26 * envelope;

      // Cheap luminous outer halo stroke in dark mode (zero blur filter cost).
      if (dark && meter.active && amp > 0.12) {
        glowPaint
          ..color = barColor.withValues(alpha: (alpha * 0.22).clamp(0.0, 0.26))
          ..strokeWidth = 6.8 + amp * 1.4;
        canvas.drawLine(
          Offset(x, size.height / 2 - height),
          Offset(x, size.height / 2 + height),
          glowPaint,
        );
      }

      corePaint
        ..color = barColor.withValues(alpha: alpha)
        ..strokeWidth = 2.8 + amp * 0.7;

      canvas.drawLine(
        Offset(x, size.height / 2 - height),
        Offset(x, size.height / 2 + height),
        corePaint,
      );
    }
  }

  @override
  bool shouldRepaint(RecordingWavePainter oldDelegate) =>
      oldDelegate.meter != meter ||
      oldDelegate.color != color ||
      oldDelegate.lowColor != lowColor ||
      oldDelegate.peakColor != peakColor ||
      oldDelegate.dark != dark;
}
