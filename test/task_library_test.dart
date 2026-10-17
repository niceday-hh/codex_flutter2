import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a thousand completed tasks are collapsed and searchable without building their cards', (tester) async {
    final records = List.generate(1000, (i) => Reminder(id: i + 2, text: '收纳记录 $i', enabled: false).toJson()
      ..['completed'] = true ..['lastAck'] = i + 1000);
    records.insert(0, Reminder(id: 1, text: '下一条待办').toJson());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async =>
      call.method == 'getState' ? jsonEncode({'reminders': records, 'status': {'notifications': true, 'exact': true}}) : null);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    expect(find.text('收纳记录 999'), findsNothing);
    expect(find.byType(Dismissible), findsOneWidget);
    await tester.tap(find.byTooltip('任务收纳')); await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索任务内容'), '收纳记录 999'); await tester.pumpAndSettle();
    expect(find.text('收纳记录 999'), findsOneWidget); expect(find.text('收纳记录 998'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('swiping asks before deletion or archive and archived task can be reused', (tester) async {
    var record = Reminder(id: 1, text: '可复用的任务').toJson();
    var archives = 0, deletes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [record], 'status': {'notifications': true, 'exact': true}});
      if (call.method == 'archive') { archives++; record = {...record, 'archived': true, 'archivedAt': 10000, 'enabled': false, 'completed': true}; }
      if (call.method == 'delete') deletes++;
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    await tester.drag(find.byType(Dismissible), const Offset(-400, 0)); await tester.pumpAndSettle();
    expect(find.text('完成后如何保留？'), findsOneWidget);
    await tester.tap(find.text('取消')); await tester.pumpAndSettle();
    expect(archives, 0); expect(deletes, 0);
    await tester.drag(find.byType(Dismissible), const Offset(-400, 0)); await tester.pumpAndSettle();
    await tester.tap(find.text('归档保留')); await tester.pumpAndSettle();
    expect(archives, 1); expect(deletes, 0); expect(find.byType(Dismissible), findsNothing);
    await tester.tap(find.byTooltip('任务收纳')); await tester.pumpAndSettle();
    await tester.tap(find.text('已归档')); await tester.pumpAndSettle();
    expect(find.text('可复用的任务'), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作')); await tester.pumpAndSettle();
    expect(find.text('编辑并复用'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
