import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/settings_page.dart';

Future<void> openSettings(WidgetTester tester, String category) async {
  tester.view.devicePixelRatio = 1; tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
  await tester.tap(find.text(category)); await tester.pumpAndSettle();
}
Finder sheetText(String text) => find.descendant(of: find.byType(SettingsSheet), matching: find.text(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fails in [false, true]) {
    testWidgets('test reminder shows ${fails ? 'error' : 'success'} inside the open sheet and sends once', (tester) async {
      final finished = Completer<void>(); var tests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {'notifications': true, 'exact': true}});
        if (call.method == 'requestNotifications') return true;
        if (call.method == 'testReminder') { tests++; await finished.future; if (fails) throw PlatformException(code: 'test', message: '测试提醒创建失败'); return 1; }
        return null;
      });
      await openSettings(tester, '帮助与诊断');
      final tile = find.widgetWithText(SettingsActionTile, '15秒后发送测试提醒');
      await tester.ensureVisible(tile); await tester.pump();
      final action = tester.widget<SettingsActionTile>(tile);
      final tap = tester.widget<ListTile>(find.descendant(of: tile, matching: find.byType(ListTile))).onTap!;
      tap(); tap(); await tester.pump(); expect(tests, 1);
      expect(find.descendant(of: tile, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      finished.complete(); await tester.pumpAndSettle();
      final message = fails ? '测试提醒创建失败' : '测试提醒已设置，请返回桌面等待15秒';
      expect(sheetText(message), findsOneWidget);
      expect(find.byType(SettingsSheet), findsOneWidget); expect(tests, 1);
      expect(tester.getRect(sheetText(message)).bottom, lessThanOrEqualTo(852));
      expect(action.title, '15秒后发送测试提醒');
      await tester.pumpWidget(const SizedBox()); await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('saving a switch gives visible feedback and reloads state once', (tester) async {
    var defaults = <String, dynamic>{}; var saves = 0, loads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') { loads++; return jsonEncode({'reminders': [], 'defaults': defaults, 'status': {'notifications': true, 'exact': true}}); }
      if (call.method == 'saveDefaults') { saves++; defaults = jsonDecode(call.arguments as String) as Map<String, dynamic>; }
      return null;
    });
    await openSettings(tester, '语音录入'); final before = loads;
    await tester.tap(find.widgetWithText(SwitchListTile, '打开应用后预听')); await tester.pumpAndSettle();
    expect(saves, 1); expect(loads - before, 1); expect(defaults['handsFree'], true);
    expect(sheetText('设置已保存'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '打开应用后预听')).value, true);
    await tester.pumpWidget(const SizedBox()); await tester.pump(); expect(tester.takeException(), isNull);
  });
  testWidgets('denied notification permission is explained inside the sheet without creating a test', (tester) async {
    var tests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {'notifications': false, 'exact': true}});
      if (call.method == 'requestNotifications') return false;
      if (call.method == 'testReminder') tests++;
      return null;
    });
    await openSettings(tester, '帮助与诊断');
    await tester.tap(find.text('15秒后发送测试提醒')); await tester.pumpAndSettle();
    expect(tests, 0); expect(sheetText('请先开启通知权限后再测试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  for (final fails in [false, true]) {
    testWidgets('vibration preview has immediate ${fails ? 'error' : 'progress'} feedback and never changes selection', (tester) async {
      final reply = Completer<String?>(); var requests = 0; String? selected;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'previewVibration') { requests++; return reply.future; }
        return null;
      });
      tester.view.devicePixelRatio = 1; tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async { selected = await chooseVibration(context, 'once'); }, child: const Text('打开'))))));
      await tester.tap(find.text('打开')); await tester.pumpAndSettle();
      final button = find.widgetWithIcon(IconButton, Icons.vibration).at(2);
      final preview = tester.widget<IconButton>(button).onPressed!; preview(); preview(); await tester.pump();
      expect(requests, 1); expect(find.text('正在试振：振动三次…'), findsOneWidget); expect(selected, isNull);
      if (fails) { reply.completeError(PlatformException(code: 'haptic', message: '系统触感反馈已关闭')); }
      else { reply.complete(jsonEncode({'requested': true, 'durationMs': 1000})); }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vibration-feedback')), findsOneWidget);
      expect(find.textContaining(fails ? '系统触感反馈已关闭' : '已发送振动三次试振请求'), findsOneWidget);
      expect(selected, isNull);
      await tester.pumpWidget(const SizedBox()); await tester.pump(); expect(tester.takeException(), isNull);
    });
  }
}
