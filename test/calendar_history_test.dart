import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
void main() {
  test('retained history belongs to its planned date and does not project past recurrences', () {
    final date = DateTime(2030, 1, 1, 10);
    final completed = Reminder(id: 1, date: date, completed: true, enabled: false);
    final archived = Reminder(id: 2, date: date, repeat: 'daily', archived: true, enabled: false);
    expect(calendarOccursOn(completed, date), isTrue);
    expect(calendarOccursOn(archived, date), isTrue);
    expect(calendarOccursOn(archived, date.add(const Duration(days: 1))), isFalse);
    final lastOccurrence = date.add(const Duration(days: 4));
    final recurring = Reminder(date: date, repeat: 'daily', archived: true, activeOccurrence: lastOccurrence.millisecondsSinceEpoch);
    expect(calendarOccursOn(recurring, lastOccurrence), isTrue);
    expect(calendarOccursOn(recurring, date), isFalse);
    expect(calendarOccursOn(Reminder(date: date, repeat: 'daily'), date.add(const Duration(days: 1))), isTrue);
  });
}
