import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/design_tokens.dart';
import 'package:timed_memo/voice_flow.dart';
import 'package:timed_memo/widgets/widgets.dart';

import 'voice_flow_test.dart' show FakeCapture, FakeStore;

/// Guards for the design system and the two performance fixes that are easy to
/// undo by accident: the 1s countdown rebuild and the offscreen blur.
void main() {
  test('every raw colour lives in design_tokens.dart', () {
    final offenders = <String>[];
    final colour = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
    final smallText = RegExp(r'fontSize:\s*(?:[0-9]|1[01])(?:\.[0-9]+)?\s*[,)]');
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('design_tokens.dart') || entity.path.endsWith('app_style.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in colour.allMatches(source)) {
        offenders.add('${entity.path}: ${match.group(0)}');
      }
      if (smallText.hasMatch(source)) offenders.add('${entity.path}: font size below 12px');
    }
    expect(offenders, isEmpty, reason: 'hard-coded values found:\n${offenders.join('\n')}');
  });

  test('nothing in the app uses an offscreen BackdropFilter', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final used = entity.readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .any((line) => line.contains('BackdropFilter('));
      if (used) offenders.add(entity.path);
    }
    expect(offenders, isEmpty, reason: 'blur re-introduced in: ${offenders.join(', ')}');
  });

  test('countdown ticks never notify the flow listeners', () {
    final flow = VoiceFlow(capture: FakeCapture(), store: FakeStore(),
      openVoicePage: () {}, onSaved: () async {});
    var notifications = 0;
    flow.addListener(() => notifications++);
    flow.secondsLeft = 12;
    expect(flow.countdown.value, 12);
    expect(flow.secondsLeft, 12);
    expect(notifications, 0, reason: 'a tick must repaint only the label that shows it');
    flow.dispose();
  });

  testWidgets('slide to confirm ignores short drags and fires once past the threshold', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 300,
      child: MemoSlideToConfirm(label: '向右滑动确认已读', onConfirm: () async { confirmed++; }))))));
    await tester.drag(find.byType(MemoSlideToConfirm), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(confirmed, 0);
    await tester.drag(find.byType(MemoSlideToConfirm), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(tester.takeException(), isNull);
  });

  test('no animation in the app loops', () {
    // The frame budget rule from the analysis: motion is a one-shot response to
    // input. A `repeat()` anywhere is an idle animation and immediately fails.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//'));
      for (final line in lines) {
        if (line.contains('.repeat(') || line.contains('repeat(reverse')) {
          offenders.add('${entity.path}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'idle animation added:\n${offenders.join('\n')}');
  });

  testWidgets('a settled reveal paints nothing extra', (tester) async {
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr,
      child: MemoReveal(animation: const AlwaysStoppedAnimation(1), child: const Text('done'))));
    expect(find.byType(Opacity), findsNothing,
      reason: 'a finished entrance must not keep a compositing layer alive');
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('an unfinished reveal does paint the offset and the alpha', (tester) async {
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr,
      child: MemoReveal(animation: const AlwaysStoppedAnimation(.4), child: const Text('mid'))));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, .4);
    expect(tester.widget<Transform>(find.byType(Transform)), isNotNull);
  });

  test('the dark palette keeps its own text readable', () {
    double lum(Color c) {
      double channel(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
      return .2126 * channel(c.r) + .7152 * channel(c.g) + .0722 * channel(c.b);
    }
    double ratio(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
    }
    final c = MemoPalette.dark;
    expect(ratio(c.ink, c.surface), greaterThan(4.5), reason: 'body text');
    expect(ratio(c.muted, c.surface), greaterThan(4.5), reason: 'captions');
    expect(ratio(c.brand700, c.surface), greaterThan(4.5), reason: 'links');
    expect(ratio(c.outline, c.surface), greaterThan(3.0), reason: 'input borders (1.4.11)');
    expect(ratio(c.canvas, c.surface), isNot(1.0), reason: 'page and card must differ');
  });

  testWidgets('the design tokens are registered on the theme', (tester) async {
    late MemoTokens tokens;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [MemoTokens.light]),
      home: Builder(builder: (context) { tokens = MemoTokens.of(context); return const SizedBox(); })));
    expect(tokens.colors.brand500, MemoColor.brand500);
    expect(tokens.colors.ink, MemoColor.ink);
    // The dark palette is a real second instance, not a copy of the light one.
    expect(MemoTokens.dark.colors.canvas, isNot(MemoTokens.light.colors.canvas));
    expect(MemoTokens.dark.colors.ink, isNot(MemoTokens.light.colors.ink));
  });
}
