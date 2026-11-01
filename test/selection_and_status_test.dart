import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/widgets/widgets.dart';

/// The four reports from 2026-11-01: a lone reminder had no archive/delete
/// exit, states were one grey sentence, and batch mode existed only on the
/// home tab.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime later({int hours = 2}) => DateTime.now().add(Duration(hours: hours));

  void mock(List<Map<String, dynamic>> rows, {void Function(MethodCall)? onCall}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native,
      (call) async {
      if (call.method == 'getState') {
        return jsonEncode({'reminders': rows, 'status': {'notifications': true, 'exact': true}});
      }
      onCall?.call(call);
      return null;
    });
  }

  testWidgets('the last reminder keeps its archive and delete exits', (tester) async {
    var archives = 0;
    mock([Reminder(id: 1, text: '交房租', date: later()).toJson()],
      onCall: (call) { if (call.method == 'archive') archives++; });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();

    // The card summarises the one reminder and the list still lists it, so
    // the task has both exits: the card's ⋯ and the row's own.
    expect(find.byType(Dismissible), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    expect(find.text('结束并保留'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('结束并保留'));
    await tester.pumpAndSettle();
    expect(find.text('结束后如何处理？'), findsOneWidget);
    await tester.tap(find.text('保留到历史'));
    await tester.pumpAndSettle();
    expect(archives, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('long-pressing the card starts batch mode even when it is the only row', (tester) async {
    mock([Reminder(id: 1, text: '交房租', date: later()).toJson()]);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('交房租').first);
    await tester.pumpAndSettle();
    // The card gives up its slot while picking, so the reminder comes back as
    // a tickable row instead of disappearing behind the selection bar.
    expect(find.text('已选 1 条'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('交房租'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('batch mode works inside the history page without backing out', (tester) async {
    mock([
      // `toJson` carries the editable fields only; `completed` and `lastAck`
      // are runtime state the native side writes back, so a fixture that only
      // serialises gets neither and the history page stays empty.
      Reminder(id: 1, text: '旧任务一', enabled: false, completed: true).toJson()
        ..['completed'] = true ..['lastAck'] = 1000,
      Reminder(id: 2, text: '旧任务二', enabled: false, completed: true).toJson()
        ..['completed'] = true ..['lastAck'] = 2000,
    ]);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史任务'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('旧任务一'));
    await tester.pumpAndSettle();
    // The bar belongs to this route. Previously it lived on the home state, so
    // nothing moved until the user backed out.
    expect(find.text('已选 1 条'), findsOneWidget);
    await tester.tap(find.text('旧任务二'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条'), findsOneWidget);
    await tester.tap(find.byTooltip('取消选择'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('each state reads as its own colour-coded chip', (tester) async {
    mock([
      // Promoted to the card, so the rows below own the chips under test.
      Reminder(id: 1, text: '主卡任务', date: later(hours: 1)).toJson(),
      // Same reason: `speechState` is computed natively, so it has to be
      // written onto the payload the mock returns.
      Reminder(id: 2, text: '准备中的任务', date: later(hours: 2), repeat: 'daily').toJson()
        ..['speechState'] = 'preparing',
      Reminder(id: 3, text: '已就绪的任务', date: later(hours: 3)).toJson()
        ..['speechState'] = 'ready',
      Reminder(id: 4, text: '失败的任务', date: later(hours: 4)).toJson()
        ..['speechState'] = 'error',
    ]);
    await tester.binding.setSurfaceSize(const Size(393, 900));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();

    expect(find.text('语音准备中'), findsOneWidget);
    expect(find.text('语音就绪'), findsOneWidget);
    expect(find.text('语音失败'), findsOneWidget);
    expect(find.text('每天'), findsOneWidget);
    // An off reminder says nothing about speech instead of adding a grey chip.
    expect(find.text('语音待准备'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  test('a selection keeps only ids that still exist', () {
    final selection = MemoSelection();
    selection
      ..toggle(1)
      ..toggle(2)
      ..toggle(3);
    expect(selection.length, 3);
    selection.retain([2, 3]);
    expect(selection.ids, {2, 3});
    selection.removeAll([3]);
    expect(selection.ids, {2});
    selection.setAll([7, 8]);
    expect(selection.ids, {7, 8});
    selection.clear();
    expect(selection.active, isFalse);
  });

  testWidgets('完成本次 skips a future repeat instead of refusing it', (tester) async {
    final calls = <String>[];
    mock([Reminder(id: 1, text: '每天喝水', date: later(hours: 3), repeat: 'daily').toJson()],
      onCall: (call) { calls.add(call.method); });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('每天喝水').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成本次'));
    await tester.pumpAndSettle();

    // Not `ack`: nothing rang. The engine advances the repeat past the
    // occurrence it was about to fire, which is "skip today's reminder".
    expect(calls, contains('skip'));
    expect(calls, isNot(contains('ack')));
    expect(find.text('1 条循环任务已跳到下一次'), findsOneWidget);
    expect(find.text('无需完成本次'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('an ended repeat reopens from its row in one tap', (tester) async {
    Map<String, dynamic>? saved;
    mock([
      Reminder(id: 1, text: '每天拉伸', enabled: false, completed: true, repeat: 'daily',
        date: DateTime.now().subtract(const Duration(days: 2))).toJson()
        ..['completed'] = true ..['lastAck'] = 1000,
    ], onCall: (call) {
      if (call.method == 'save') saved = jsonDecode(call.arguments as String) as Map<String, dynamic>;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史任务'));
    await tester.pumpAndSettle();

    // A repeat still has a rule to run, so its pill is the verb (开启); a
    // one-shot would show 编辑 because there is no date left to re-arm.
    expect(find.text('开启'), findsOneWidget);
    await tester.tap(find.text('开启'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!['archived'], isFalse);
    expect(saved!['enabled'], isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('a history row deletes only after the dialog confirms', (tester) async {
    var deletes = 0;
    mock([
      Reminder(id: 2, text: '一次性任务', enabled: false, completed: true).toJson()
        ..['completed'] = true ..['lastAck'] = 1000,
    ], onCall: (call) { if (call.method == 'delete') deletes++; });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史任务'));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('history-2'));
    await tester.drag(row, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除这条历史任务？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(deletes, 0);

    await tester.drag(row, const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
