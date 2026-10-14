import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async => switch (call.method) {
        'getState' => jsonEncode({'reminders': [], 'defaults': {}, 'status': {'notifications': true, 'exact': true, 'battery': false, 'lastError': ''}}),
        'initialReminderId' => 0,
        _ => null,
      });
  });
  testWidgets('four tabs and editor fit phone viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('留一点空间，给重要的事'), findsOneWidget);
    for (final label in ['日历', '语音', '设置', '备忘录']) {
      await tester.tap(find.text(label).last); await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('新建提醒')); await tester.pumpAndSettle();
    expect(find.text('小型系统弹窗'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('未读再次提醒'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('未读再次提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
