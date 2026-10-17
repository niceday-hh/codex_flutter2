import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/recording_waveform.dart';

void main() {
  test('waveform is driven by measured sound, has a fixed history, and resets', () {
    final meter = RecordingMeter();
    meter.accept({'dbfs': -12.0, 'peak': 0.6});
    expect(meter.level, 0); // No microphone visualization while idle.
    meter.start(); meter.accept({'dbfs': -90.0, 'peak': 0.0});
    expect(meter.level, 0);
    meter.accept({'dbfs': -20.0, 'peak': 0.5});
    final quiet = meter.level;
    meter.accept({'dbfs': -5.0, 'peak': 0.99});
    expect(meter.level, greaterThan(quiet)); expect(meter.description, contains('满幅'));
    for (var i = 0; i < 1000; i++) { meter.accept({'dbfs': -30.0, 'peak': 0.2}); }
    expect(meter.levels.length, 33);
    meter.accept({'dbfs': double.nan, 'peak': 0.2}); expect(meter.level.isFinite, isTrue);
    meter.stop(); expect(meter.levels.every((v) => v == 0), isTrue);
    meter.accept({'dbfs': -2.0, 'peak': 0.99}); expect(meter.level, 0);
    meter.dispose();
  });
  testWidgets('idle waveform has no animation timer and reflects live PCM levels', (tester) async {
    final meter = RecordingMeter();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecordingWaveform(meter: meter))));
    expect(find.text('波形显示实际录音音量'), findsOneWidget);
    meter.start(); meter.accept({'dbfs': -50.0, 'peak': 0.01}); await tester.pump();
    expect(find.text('声音偏小，请靠近麦克风'), findsOneWidget);
    meter.accept({'dbfs': -23.0, 'peak': 0.3}); await tester.pump();
    expect(find.text('收音适中'), findsOneWidget);
    meter.stop(); await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox()); meter.dispose();
    expect(tester.takeException(), isNull);
  });
}
