import 'dart:io';

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

  testWidgets('the design tokens are registered on the theme', (tester) async {
    late MemoTokens tokens;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [MemoTokens.light]),
      home: Builder(builder: (context) { tokens = MemoTokens.of(context); return const SizedBox(); })));
    expect(tokens.brand, MemoColor.brand500);
  });
}
