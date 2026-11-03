import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/widgets/widgets.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/settings_page.dart';
import 'package:timed_memo/task_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('opening and updating a detail defers covered home builds until dismissal', (tester) async {
    var body = '打开前的提醒';
    final reminder = Reminder(id: 7, text: body);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') {
        return jsonEncode({'reminders': [{...reminder.toJson(), 'text': body}],
          'defaults': {}, 'status': {'notifications': true, 'exact': true}});
      }
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, null));
    // Open while the home entrance is still running, not only after it settles.
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 300));
    final home = find.descendant(of: find.byType(MemoHome), matching: find.byType(Scaffold)).first;
    final before = tester.widget<Scaffold>(home);
    await tester.tap(find.text(body).first); await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(home), same(before), reason: 'voice pause must not rebuild the covered tabs');
    body = '弹窗期间收到的新内容';
    final response = Completer<void>();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage('memo/native',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('stateChanged')),
      (_) => response.complete());
    await tester.pump(); await response.future; await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(home), same(before));
    Navigator.of(tester.element(find.byType(ReminderDetail))).pop(); await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(home), isNot(same(before)));
    expect(find.text(body), findsWidgets, reason: 'updates must not be lost while the modal is open');
    await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
  });
  testWidgets('history opens on the first tap and repeated taps cannot queue routes while stop is pending', (tester) async {
    final stopped = Completer<void>(); var cancellations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {'notifications': true, 'exact': true}});
      if (call.method == 'cancelRecording') { cancellations++; await stopped.future; }
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    final openHistory = tester.widget<MemoIconButton>(find.widgetWithIcon(MemoIconButton, Icons.inventory_2_outlined)).onTap!;
    await tester.tap(find.byTooltip('历史任务'));
    openHistory(); openHistory();
    await tester.pumpAndSettle();
    expect(find.byType(TaskLibraryPage), findsOneWidget);
    expect(cancellations, 1);
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(find.byType(TaskLibraryPage), findsNothing);
    expect(find.byType(MemoTabBar), findsOneWidget);
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
  for (final openEditor in [false, true]) {
    testWidgets('${openEditor ? 'editor' : 'detail'} opens once while ASR startup and recorder cancellation are pending', (tester) async {
      final assets = Completer<String?>(), stopped = Completer<void>();
      var stopCalls = 0;
      final reminder = Reminder(text: '尚在准备的提醒', speechMode: 'on')..id = 7;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'getState') return jsonEncode({'reminders': [reminder.toJson()], 'defaults': {'handsFree': true}, 'status': {'notifications': true, 'exact': true}});
        if (call.method == 'voiceEntryAllowed') return true;
        if (call.method == 'prepareAsr') return assets.future;
        if (call.method == 'cancelRecording' && ++stopCalls > 1) await stopped.future;
        return null;
      });
      await tester.binding.setSurfaceSize(const Size(393, 852));
      await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 300));
      final callback = openEditor
        ? tester.widget<MemoTabBar>(find.byType(MemoTabBar)).onCreate!
        : tester.widget<InkWell>(find.ancestor(of: find.text('尚在准备的提醒').first, matching: find.byType(InkWell)).first).onTap!;
      callback(); callback(); callback();
      await tester.pumpAndSettle();
      expect(find.byType(openEditor ? ReminderEditor : ReminderDetail), findsOneWidget);
      Navigator.of(tester.element(find.byType(openEditor ? ReminderEditor : ReminderDetail))).pop(); await tester.pumpAndSettle();
      expect(find.byType(openEditor ? ReminderEditor : ReminderDetail), findsNothing);
      assets.complete(null); stopped.complete(); await tester.pump();
      await tester.pumpWidget(const SizedBox()); await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('settings categories hide parameters and search opens the matching sheet without saving', (tester) async {
    var saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {'notifications': true, 'exact': true}});
      if (call.method == 'saveDefaults') saves++;
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(MemoTabBar), matching: find.text('设置'))); await tester.pumpAndSettle();
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
    expect(find.descendant(of: find.byType(SettingsSheet), matching: find.text('自动停录等待')), findsOneWidget);
    expect(find.text('已定位：自动停录等待'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭设置分类')); await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsNothing); expect(saves, 0);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
