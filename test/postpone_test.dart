import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('postpone sends the target in milliseconds and returns the armed time', () async {
    Map<String, dynamic>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native, (call) async {
        if (call.method == 'getState') return jsonEncode({'reminders': []});
        if (call.method == 'postpone') {
          arguments = Map<String, dynamic>.from(call.arguments as Map);
          return 1893456000000;
        }
        return null;
      });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null));

    final target = DateTime(2030, 1, 1, 8);
    final landed = await MemoStore().postpone(Reminder(id: 9), target);
    expect(arguments?['id'], 9);
    expect(arguments?['at'], target.millisecondsSinceEpoch);
    expect(landed, DateTime.fromMillisecondsSinceEpoch(1893456000000));
  });

  test('postpone reports null when the engine declines', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native, (call) async => switch (call.method) {
        'getState' => jsonEncode({'reminders': []}),
        'postpone' => 0,
        _ => null,
      });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null));
    expect(await MemoStore().postpone(Reminder(id: 9), DateTime.now().add(const Duration(hours: 1))), isNull);
  });

  testWidgets('a future task offers quick postponement based on its own time', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null));
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(hours: 2));
    DateTime? asked;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReminderDetail(
      reminder: Reminder(id: 1, text: '交房租', date: at),
      onAck: () async {}, onSkip: () async {},
      onPostpone: (value) async { asked = value; return value; },
      onEdit: () {},
    ))));
    await tester.pumpAndSettle();

    expect(find.text('延后提醒'), findsOneWidget);
    await tester.tap(find.text('+15 分钟'));
    await tester.pumpAndSettle();
    expect(asked, at.add(const Duration(minutes: 15)));
  });

  testWidgets('a ringing task has no postponement — its exit is acknowledge', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null));
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReminderDetail(
      reminder: Reminder(id: 1, text: '交房租', activeOccurrence: DateTime.now().millisecondsSinceEpoch),
      onAck: () async {}, onSkip: () async {},
      onPostpone: (value) async => value,
      onEdit: () {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('延后提醒'), findsNothing);
  });

  testWidgets('the editor carries the same steps and keeps the clock in sync', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null));
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(hours: 2));
    await tester.pumpWidget(MaterialApp(home: ReminderEditor(
      reminder: Reminder(id: 1, text: '交房租', date: at), store: MemoStore())));
    await tester.pumpAndSettle();

    final expected = at.add(const Duration(minutes: 15));
    await tester.ensureVisible(find.text('+15 分钟'));
    await tester.tap(find.text('+15 分钟'));
    await tester.pumpAndSettle();
    expect(find.text('${expected.hour.toString().padLeft(2, '0')}:'
        '${expected.minute.toString().padLeft(2, '0')}:00'), findsOneWidget);
  });
}
