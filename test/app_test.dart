import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';

Future<void> revealByDragging(WidgetTester tester, Finder target, Finder scrollable) async {
  for (var i = 0; i < 40 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -180));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async => switch (call.method) {
        'getState' => jsonEncode({'reminders': [], 'defaults': {}, 'status': {'notifications': true, 'exact': true, 'battery': false, 'lastError': ''}}),
        'initialReminderId' => 0,
        _ => null,
      });
  });
  testWidgets('four tabs and editor fit phone viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('留一点空间，给重要的事'), findsOneWidget);
    for (final label in ['日历', '语音', '设置', '备忘录']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)).last);
      await tester.pump(); await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('新建提醒')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('展示方式'), 250, scrollable: find.byType(Scrollable).last);
    expect(find.text('展示方式'), findsOneWidget);
    expect(find.text('横幅和通知栏'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('未读再次提醒'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('未读再次提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('inactive records remain visible on home', (tester) async {
    final record = Reminder(id: 7, text: '迁移后未启用的提醒', enabled: false).toJson();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async => call.method == 'getState'
        ? jsonEncode({'reminders': [record], 'defaults': {}, 'status': {'notifications': true, 'exact': true}}) : null);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('迁移后未启用的提醒'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('迁移后未启用的提醒'), findsOneWidget);
    expect(find.text('未启用'), findsWidgets);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('editing completed reminder saves an enabled future task', (tester) async {
    Map<String, dynamic> record = Reminder(id: 7, text: '已完成任务重新启用', enabled: false,
      completed: true, date: DateTime.now().add(const Duration(hours: 1))).toJson()..['completed'] = true;
    Map<String, dynamic>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async {
        if (call.method == 'getState') { return jsonEncode({'reminders': [record], 'defaults': {}, 'status': {'notifications': true, 'exact': true}}); }
        if (call.method == 'requestNotifications') { return true; }
        if (call.method == 'save') { saved = jsonDecode(call.arguments as String) as Map<String, dynamic>; record = saved!; }
        return null;
      });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('已完成任务重新启用'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('已完成任务重新启用')); await tester.pumpAndSettle();
    await tester.tap(find.text('编辑提醒')); await tester.pumpAndSettle();
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(saved?['enabled'], isTrue);
    expect(find.text('已完成任务重新启用'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('new display defaults persist and are inherited by a saved reminder', (tester) async {
    Map<String, dynamic> defaults = {};
    Map<String, dynamic>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native, (call) async {
        if (call.method == 'getState') { return jsonEncode({'reminders': [], 'defaults': defaults, 'status': {'notifications': true, 'exact': true}}); }
        if (call.method == 'saveDefaults') { defaults = jsonDecode(call.arguments as String) as Map<String, dynamic>; }
        if (call.method == 'save') { saved = jsonDecode(call.arguments as String) as Map<String, dynamic>; }
        return null;
      });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
    final settingsScroll = find.descendant(of: find.byType(IndexedStack), matching: find.byType(Scrollable)).last;
    await tester.scrollUntilVisible(find.text('默认展示方式'), 200, scrollable: settingsScroll);
    await tester.tap(find.text('默认展示方式')); await tester.pumpAndSettle();
    await tester.tap(find.text('仅通知栏').last); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('默认锁屏显示'), 150, scrollable: settingsScroll);
    await tester.tap(find.text('默认锁屏显示')); await tester.pumpAndSettle();
    await tester.tap(find.text('不在锁屏显示').last); await tester.pumpAndSettle();
    expect(defaults['presentation'], 'drawer'); expect(defaults['lockscreen'], 'hidden');
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('备忘录'))); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建提醒')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '验证默认展示设置');
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(saved?['presentation'], 'drawer'); expect(saved?['lockscreen'], 'hidden');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('editor system shortcut uses current unsaved style without saving a reminder', (tester) async {
    Map<String, dynamic>? opened;
    int saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native, (call) async {
        if (call.method == 'notificationStyleSettings') { opened = jsonDecode(call.arguments as String) as Map<String, dynamic>; }
        if (call.method == 'save') { saves++; }
        return null;
      });
    final store = MemoStore();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(MaterialApp(home: ReminderEditor(reminder: Reminder(text: '未保存'), store: store)));
    await tester.scrollUntilVisible(find.text('展示方式'), 250, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('展示方式')); await tester.pumpAndSettle();
    await tester.tap(find.text('仅通知栏').last); await tester.pumpAndSettle();
    await tester.tap(find.text('锁屏显示')); await tester.pumpAndSettle();
    await tester.tap(find.text('不在锁屏显示').last); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('这条提醒的系统通知设置'), 150, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('这条提醒的系统通知设置')); await tester.pumpAndSettle();
    expect(opened?['presentation'], 'drawer'); expect(opened?['lockscreen'], 'hidden');
    expect(opened?.containsKey('text'), isFalse); expect(saves, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('self check has one global entry and folded referenced style groups', (tester) async {
    String? opened;
    final styles = [
      {'id': 'style-a', 'name': '横幅提醒 · 振动三次', 'count': 8, 'isDefault': true, 'importance': 4},
      {'id': 'style-b', 'name': '仅通知栏 · 不振动', 'count': 2, 'isDefault': false, 'importance': 3},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native, (call) async {
        if (call.method == 'getState') { return jsonEncode({'reminders': [], 'defaults': {}, 'status': {
          'notifications': true, 'exact': true, 'notificationStyles': styles, 'hiddenChannelCount': 5}}); }
        if (call.method == 'channelSettings') { opened = call.arguments as String; }
        return null;
      });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
    final settingsScroll = find.descendant(of: find.byType(IndexedStack), matching: find.byType(Scrollable)).last;
    await revealByDragging(tester, find.text('检查系统通知与锁屏设置'), settingsScroll);
    expect(find.text('检查系统通知与锁屏设置'), findsOneWidget);
    expect(find.text('检查通知横幅与锁屏显示'), findsNothing);
    await revealByDragging(tester, find.text('通知样式（2种）'), settingsScroll);
    expect(find.text('横幅提醒 · 振动三次'), findsNothing);
    await tester.tap(find.text('通知样式（2种）')); await tester.pumpAndSettle();
    await revealByDragging(tester, find.text('仅通知栏 · 不振动'), settingsScroll);
    expect(find.textContaining('关联 8 条备忘'), findsOneWidget);
    expect(find.textContaining('关联 2 条备忘'), findsOneWidget);
    await tester.tap(find.text('仅通知栏 · 不振动')); await tester.pumpAndSettle();
    expect(opened, 'style-b');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
