import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/reminder_search.dart';

void main() {
  test('display clock follows snooze and active occurrence, original clock stays editable', () {
    final r = Reminder(date: DateTime(2030, 1, 1, 9),
      nextTrigger: DateTime(2030, 1, 1, 9, 10).millisecondsSinceEpoch);
    expect(r.time, '09:00');
    expect(r.displayTime, '09:10');
    r.activeOccurrence = DateTime(2030, 1, 1, 9, 10).millisecondsSinceEpoch;
    r.nextTrigger = DateTime(2030, 1, 2, 9).millisecondsSinceEpoch;
    expect(r.displayTime, '09:10');
    r.acknowledged = true;
    expect(r.displayTime, '09:00');
  });
  testWidgets('search clear removes visible text as well as query', (tester) async {
    await tester.pumpWidget(const MemoApp());
    final context = tester.element(find.byType(MemoHome));
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      ReminderSearchPage(reminders: [Reminder(text: '喝水')])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '喝水');
    await tester.pump();
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
    expect(find.text('输入关键词开始搜索'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
