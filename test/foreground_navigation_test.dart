import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/settings_page.dart';
import 'package:timed_memo/task_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('history opens on the first tap and repeated taps cannot queue routes while stop is pending', (tester) async {
    final stopped = Completer<void>(); var cancellations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {'notifications': true, 'exact': true}});
      if (call.method == 'cancelRecording') { cancellations++; await stopped.future; }
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    final openHistory = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.inventory_2_outlined)).onPressed!;
    await tester.tap(find.byTooltip('历史任务'));
    openHistory(); openHistory();
    await tester.pumpAndSettle();
    expect(find.byType(TaskLibraryPage), findsOneWidget);
    expect(cancellations, 1);
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(find.byType(TaskLibraryPage), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    stopped.complete(); await tester.pump();
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('history also opens while initial ASR assets are still preparing', (tester) async {
    final assets = Completer<String?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {'notifications': true, 'exact': true}});
      if (call.method == 'voiceEntryAllowed') return true;
      if (call.method == 'prepareAsr') return assets.future;
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('历史任务')); await tester.pumpAndSettle();
    expect(find.byType(TaskLibraryPage), findsOneWidget);
    assets.complete(null); await tester.pump();
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(find.byType(TaskLibraryPage), findsNothing);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings categories hide parameters and search opens the matching sheet without saving', (tester) async {
    var saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {'notifications': true, 'exact': true}});
      if (call.method == 'saveDefaults') saves++;
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
    for (final section in settingsSections) { expect(find.text(section.title), findsOneWidget); }
    expect(find.text('自动停录等待'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('settings-search')), '自动停录'); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-result-silence')), findsOneWidget);
    expect(find.text('任务与数据'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-result-silence'))); await tester.pumpAndSettle();
    expect(find.text('当前：5 秒'), findsOneWidget);
    expect(find.text('选择连续安静多少秒后结束录音。'), findsWidgets);
    await tester.tap(find.text('前往设置')); await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsOneWidget);
    expect(find.text('自动停录等待'), findsOneWidget);
    expect(find.text('已定位：自动停录等待'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭设置分类')); await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsNothing); expect(saves, 0);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
