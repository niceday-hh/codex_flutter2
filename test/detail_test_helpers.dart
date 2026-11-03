import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercise the outer viewport and its actions. Starting in
/// the正文 would scroll only that inner viewport and never reveal the actions.
Future<void> revealDetailAction(WidgetTester tester, Finder target) async {
  final rect = tester.getRect(find.byKey(const ValueKey('reminder-detail-scroll')));
  for (var attempt = 0; attempt < 16 && target.hitTestable().evaluate().isEmpty; attempt++) {
    await tester.dragFrom(Offset(rect.right - 6, rect.bottom - 24), const Offset(0, -160));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}
