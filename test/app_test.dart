import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';

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
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)).last);
      await tester.pump(); await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('新建提醒')); await tester.pumpAndSettle();
    expect(find.text('小型系统弹窗'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('未读再次提醒'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('未读再次提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('inactive records remain visible on home', (tester) async {
    final record = Reminder(id: 7, text: '迁移后未启用的提醒', enabled: false).toJson();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async => call.method == 'getState'
        ? jsonEncode({'reminders': [record], 'defaults': {}, 'status': {'notifications': true, 'exact': true}}) : null);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('迁移后未启用的提醒'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('迁移后未启用的提醒'), findsOneWidget);
    expect(find.text('未启用'), findsWidgets);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('editing completed reminder saves an enabled future task', (tester) async {
    Map<String, dynamic> record = Reminder(id: 7, text: '已完成任务重新启用', enabled: false,
      completed: true, date: DateTime.now().add(const Duration(hours: 1))).toJson()..['completed'] = true;
    Map<String, dynamic>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async {
        if (call.method == 'getState') { return jsonEncode({'reminders': [record], 'defaults': {}, 'status': {'notifications': true, 'exact': true}}); }
        if (call.method == 'requestNotifications') { return true; }
        if (call.method == 'save') { saved = jsonDecode(call.arguments as String) as Map<String, dynamic>; record = saved!; }
        return null;
      });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('已完成任务重新启用'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('已完成任务重新启用')); await tester.pumpAndSettle();
    await tester.tap(find.text('编辑提醒')); await tester.pumpAndSettle();
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(saved?['enabled'], isTrue);
    expect(find.text('已完成任务重新启用'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
