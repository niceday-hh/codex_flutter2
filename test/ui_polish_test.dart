import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';

void mockState(List<Map<String, dynamic>> reminders) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('memo/native'), (call) async => switch (call.method) {
      'getState' => jsonEncode({'reminders': reminders, 'defaults': {},
        'status': {'version': '0.9.7', 'notifications': true, 'exact': true}}),
      'initialReminderId' => 0,
      _ => null,
    });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty home offers a create action that opens the editor', (tester) async {
    mockState(const []);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();
    expect(find.text('留一点空间，给重要的事'), findsOneWidget);
    final action = find.text('新建提醒');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('提醒内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('reminder cards keep an ink surface above an opaque material', (tester) async {
    final row = Reminder(id: 7, text: '测试卡片', date: DateTime.now().add(const Duration(hours: 2))).toJson();
    mockState([row]);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MemoApp());
    await tester.pumpAndSettle();
    final cardText = find.text('测试卡片').last;
    final ink = find.ancestor(of: cardText, matching: find.byType(InkWell));
    expect(ink, findsWidgets);
    expect(find.ancestor(of: ink.first, matching: find.byType(Material)), findsWidgets);
    expect(find.byType(Dismissible), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
