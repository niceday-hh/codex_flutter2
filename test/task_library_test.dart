import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/task_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a thousand completed tasks are collapsed and searchable without building their cards', (tester) async {
    final records = List.generate(1000, (i) => Reminder(id: i + 2, text: '收纳记录 $i', enabled: false).toJson()
      ..['completed'] = true ..['lastAck'] = i + 1000);
    // Two live rows besides the hero card's own task: the card no longer
    // removes anything from the list, so both are rows and both dismissible.
    records.insert(0, Reminder(id: 1, text: '下一条待办', date: DateTime.now().add(const Duration(hours: 2))).toJson());
    records.insert(1, Reminder(id: 1002, text: '再下一条', date: DateTime.now().add(const Duration(hours: 3))).toJson());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async =>
      call.method == 'getState' ? jsonEncode({'reminders': records, 'status': {'notifications': true, 'exact': true}}) : null);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    expect(find.text('收纳记录 999'), findsNothing);
    expect(find.byType(Dismissible), findsNWidgets(2));
    await tester.tap(find.byTooltip('历史任务')); await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索任务内容'), '收纳记录 999'); await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is Text && w.data == '收纳记录 999'), findsOneWidget);
    expect(find.text('收纳记录 998'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('swiping asks before deletion or archive and archived task can be reused', (tester) async {
    var record = Reminder(id: 1, text: '可复用的任务', date: DateTime.now().add(const Duration(hours: 2))).toJson();
    // A filler that is earlier than the row under test, so the row under test
    // is not the card's task and the drag targets a plain row.
    final filler = Reminder(id: 2, text: '占位待办', date: DateTime.now().add(const Duration(hours: 1))).toJson();
    var archives = 0, deletes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [filler, record], 'status': {'notifications': true, 'exact': true}});
      if (call.method == 'archive') { archives++; record = {...record, 'archived': true, 'archivedAt': 10000, 'enabled': false, 'completed': true}; }
      if (call.method == 'delete') deletes++;
      if (call.method == 'requestNotifications') return true;
      if (call.method == 'save') {
        final saved = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        record = {...saved, 'completed': false};
      }
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('task-1-0-0'));
    await tester.drag(row, const Offset(-400, 0)); await tester.pumpAndSettle();
    expect(find.text('结束后如何处理？'), findsOneWidget);
    await tester.tap(find.text('取消')); await tester.pumpAndSettle();
    expect(archives, 0); expect(deletes, 0);
    await tester.drag(row, const Offset(-400, 0)); await tester.pumpAndSettle();
    await tester.tap(find.text('保留到历史')); await tester.pumpAndSettle();
    expect(archives, 1); expect(deletes, 0); expect(find.byKey(const ValueKey('task-1-0-0')), findsNothing);
    await tester.tap(find.byTooltip('历史任务')); await tester.pumpAndSettle();
    expect(find.text('可复用的任务'), findsOneWidget);
    // The row now carries its verb directly: a one-shot has no rule left to
    // re-arm, so its pill is 编辑 and opens the editor in one tap.
    await tester.tap(find.text('编辑')); await tester.pumpAndSettle();
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(record['archived'], isFalse); expect(record['enabled'], isTrue);
    expect(find.byTooltip('历史任务'), findsOneWidget); expect(find.text('可复用的任务'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('completed and archived records form one history without duplicates', (tester) async {
    final store = MemoStore()..reminders = [
      Reminder(id: 1, text: '自动完成记录', enabled: false, completed: true),
      Reminder(id: 2, text: '主动保留记录', enabled: false, completed: true, archived: true),
    ];
    await tester.pumpWidget(MaterialApp(home: TaskLibraryPage(store: store, card: (r, _) => Text(r.text))));
    await tester.pumpAndSettle();
    expect(find.text('自动完成记录'), findsOneWidget); expect(find.text('主动保留记录'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.textContaining('2 条'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
