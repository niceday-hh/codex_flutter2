import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/asr.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';

void enterBackground(WidgetTester tester) {
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}
void resumeApp(WidgetTester tester) {
  for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final seconds in [0, 15, 30, 60]) {
    testWidgets('background stops the recorder while honoring the saved $seconds second model grace', (tester) async {
      var cancellations = 0, starts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'getState') {
          return jsonEncode({'reminders': [], 'defaults': {
            'asrBackgroundRetentionSeconds': seconds}, 'status': {}});
        }
        if (call.method == 'cancelRecording') { cancellations++; }
        if (call.method == 'startRecording') { starts++; }
        return null;
      });
      await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
      asr.status.value = '测试中的已加载模型';
      enterBackground(tester);
      await tester.pump();
      expect(cancellations, greaterThan(0)); expect(starts, 0);
      if (seconds == 0) {
        expect(asr.status.value, contains('已释放'));
      } else {
        expect(asr.status.value, '测试中的已加载模型');
        await tester.pump(Duration(seconds: seconds));
        expect(asr.status.value, contains('已释放'));
      }
      resumeApp(tester);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox()); await tester.pump();
    });
  }
  testWidgets('a late recorder stop from the background cannot evict a new foreground model', (tester) async {
    final stopped = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') {
        return jsonEncode({'reminders': [], 'defaults': {
          'asrBackgroundRetentionSeconds': 15}, 'status': {}});
      }
      if (call.method == 'cancelRecording') { await stopped.future; }
      return null;
    });
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    enterBackground(tester); await tester.pump();
    resumeApp(tester); await tester.pumpAndSettle();
    asr.status.value = '前台复用的模型';
    stopped.complete(); await tester.pump();
    await tester.pump(const Duration(seconds: 60));
    expect(asr.status.value, '前台复用的模型');
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
