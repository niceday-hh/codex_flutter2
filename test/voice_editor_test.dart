import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/voice_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('missing time cannot silently save a default schedule', (tester) async {
    var saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'save') saves++;
      return null;
    });
    final p = parseVoice('明天提醒我买牛奶');
    await tester.pumpWidget(MaterialApp(home: ReminderEditor(reminder: p.reminder, store: MemoStore(), voice: p)));
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(saves, 0); expect(find.text('请选择时间'), findsOneWidget);
    expect(find.textContaining('请点选时间确认'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('expired countdown requires explicit restart and saves precise new target', (tester) async {
    Map<String, dynamic>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'save') saved = jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {}});
      return null;
    });
    final p = parseVoice('五分钟后提醒我喝水', now: DateTime(2000));
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(MaterialApp(home: ReminderEditor(reminder: p.reminder, store: MemoStore(), voice: p)));
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(saved, isNull); expect(find.text('请选择未来的日期和时间'), findsOneWidget);
    await tester.tap(find.text('从现在起重新计时')); await tester.pump();
    final target = p.reminder.date;
    expect(target.isAfter(DateTime.now()), isTrue);
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(saved, isNotNull); expect(Reminder.fromJson(saved!).date, target);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
