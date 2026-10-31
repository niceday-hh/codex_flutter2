import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/appearance.dart';
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
    // Two transforms now: the upward drift and the last 0.8% of scale. Checked
    // by matrix rather than by count, so adding a third would still be caught
    // only if it stopped doing one of these two things.
    final matrices = tester.widgetList<Transform>(find.byType(Transform)).map((t) => t.transform).toList();
    expect(matrices.any((m) => m.getTranslation().y > 0), isTrue,
      reason: 'a mid-flight item sits below its final slot');
    expect(matrices.any((m) => m.storage[0] < 1), isTrue,
      reason: 'and is still slightly smaller than its final size');
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

  test('every accent ramp carries white text and reads on the page', () {
    double lum(Color c) {
      double channel(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
      return .2126 * channel(c.r) + .7152 * channel(c.g) + .0722 * channel(c.b);
    }
    double ratio(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
    }
    for (final accent in MemoAccent.values) {
      final light = MemoPalette.forAccent(accent, Brightness.light);
      final dark = MemoPalette.forAccent(accent, Brightness.dark);
      // A filled button is white on 500, a link is 700 on the card.
      expect(ratio(light.brand500, Colors.white), greaterThanOrEqualTo(4.5),
        reason: '${accent.name}: filled button label');
      expect(ratio(light.brand700, light.surface), greaterThanOrEqualTo(7.0),
        reason: '${accent.name}: links and labels');
      // In dark mode the fill carries the page colour as its label.
      expect(ratio(dark.brand500, dark.canvas), greaterThanOrEqualTo(4.5),
        reason: '${accent.name}: dark filled button label');
      expect(ratio(dark.brand700, dark.surface), greaterThanOrEqualTo(7.0),
        reason: '${accent.name}: dark links');
      expect(light.brand500, isNot(dark.brand500), reason: '${accent.name}: ramps are per-brightness');
      // The tick drawn on a selected swatch uses inkOn; it must stay legible
      // whichever swatch the contrast picker lands on.
      expect(ratio(inkOn(light.brand500), light.brand500), greaterThanOrEqualTo(4.5),
        reason: '${accent.name}: light swatch tick');
      expect(ratio(inkOn(dark.brand500), dark.brand500), greaterThanOrEqualTo(4.5),
        reason: '${accent.name}: dark swatch tick');
    }
  });

  test('the hero gradient follows the accent instead of the default violet', () {
    final teal = MemoPalette.forAccent(MemoAccent.teal, Brightness.light);
    expect(teal.heroGradientFor(12), teal.brand.gradientDay);
    expect(teal.heroGradientFor(7), teal.brand.gradientDawn);
    expect(teal.heroGradientFor(22), teal.brand.gradientNight);
    // A switched accent must not leave a violet card behind.
    expect(teal.heroGradientFor(12).first, isNot(MemoPalette.light.heroGradientFor(12).first));
  });

  test('appearance parsing tolerates unknown or missing values', () {
    expect(Appearance.modeOf(null), ThemeMode.system);
    expect(Appearance.modeOf('sepia'), ThemeMode.system);
    expect(Appearance.modeOf('dark'), ThemeMode.dark);
    expect(Appearance.accentOf('chartreuse'), MemoAccent.violet);
    expect(Appearance.accentOf('ember'), MemoAccent.ember);
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

  test('type sits on three weights and never tightens Chinese', () {
    final weights = <String>[];
    final tracking = <String>[];
    final weight = RegExp(r'FontWeight\.w(\d{3})');
    final negative = RegExp(r'letterSpacing:\s*-(?:[0-9]*\.)?[0-9]+');
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final m in weight.allMatches(source)) {
        if (!const {'400', '500', '600'}.contains(m.group(1))) {
          weights.add('${entity.path}: ${m.group(0)}');
        }
      }
      // Negative tracking is legal on exactly one thing: the tabular clocks.
      // Digits are narrow enough to take it; Han glyphs are not, and at 30px a
      // tightened bold face turns strokes into slabs.
      for (final line in source.split('\n')) {
        if (!negative.hasMatch(line)) continue;
        final isClock = line.contains('heroTime') || line.contains('cardTime') ||
          line.contains('fontFeatures');
        if (!isClock) tracking.add('${entity.path}: ${line.trim()}');
      }
    }
    // w700 and w800 were spent on 43 of 49 call sites, which is why the whole
    // app read as bold: a hierarchy where everything is loud has none.
    expect(weights, isEmpty, reason: 'weights outside 400/500/600:\n${weights.join('\n')}');
    expect(tracking, isEmpty, reason: 'negative tracking outside the clocks:\n${tracking.join('\n')}');
  });

  test('the clocks stay subordinate to the content', () {
    final t = MemoType(MemoPalette.light);
    expect(t.heroTime.fontSize, lessThanOrEqualTo(36), reason: '40px w800 swallowed the card');
    expect(t.cardTime.fontSize, lessThanOrEqualTo(24), reason: 'a 26px clock is a headline');
    expect(t.heroTime.fontWeight, FontWeight.w600);
    expect(t.cardTime.fontWeight, FontWeight.w600);
  });

  test('day headers read as a rule, not a heading', () {
    final t = MemoType(MemoPalette.dark);
    expect(t.groupLabel.fontWeight, FontWeight.w500);
    expect(t.groupLabel.color, MemoPalette.dark.muted, reason: 'ink made the pinned strip glow');
    expect(t.groupLabel.letterSpacing, isNull);
    expect(t.groupLabel.fontSize, lessThanOrEqualTo(t.caption.fontSize!));
  });

  test('the dark theme stacks three surfaces without glare', () {
    double lum(Color c) {
      double channel(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
      return .2126 * channel(c.r) + .7152 * channel(c.g) + .0722 * channel(c.b);
    }
    double ratio(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
    }
    final c = MemoPalette.dark;
    // Page → card → lifted sheet: each step has to be visible, none may glow.
    expect(ratio(c.surface, c.canvas), greaterThan(1.05), reason: 'page and card must separate');
    expect(ratio(c.surfaceAlt, c.surface), greaterThan(1.05), reason: 'a sheet must lift off a card');
    expect(ratio(c.surfaceAlt, c.surface), lessThan(1.5), reason: 'a lifted surface must not glow');
    expect(ratio(c.ink, c.surface), greaterThan(7.0), reason: 'body text keeps AAA at night');
    expect(c.ink, isNot(const Color(0xFFF3EFFA)), reason: 'white glare was dialled back');
    expect(ratio(c.line, c.surface), greaterThan(1.2), reason: 'a hairline has to be visible on #191622');
  });
}
