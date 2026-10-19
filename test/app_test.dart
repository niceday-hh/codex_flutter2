import 'dart:async';
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
    final record = Reminder(id: 7, text: '迁移后未启用的提醒', enabled: false, speechMode: 'inherit').toJson();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async => call.method == 'getState'
        ? jsonEncode({'reminders': [record], 'defaults': {}, 'status': {'notifications': true, 'exact': true}}) : null);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('迁移后未启用的提醒'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('迁移后未启用的提醒'), findsOneWidget);
    expect(find.text('未启用'), findsWidgets);
    expect(find.text('语音待准备'), findsNothing);
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
    await tester.scrollUntilVisible(find.text('历史任务 · 1 条'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('历史任务 · 1 条')); await tester.pumpAndSettle();
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
    await tester.tap(find.text('提醒与通知')); await tester.pumpAndSettle();
    final settingsScroll = find.byType(Scrollable).last;
    await revealByDragging(tester, find.text('默认展示方式'), settingsScroll);
    await tester.tap(find.text('默认展示方式')); await tester.pumpAndSettle();
    await tester.tap(find.text('仅通知栏').last); await tester.pumpAndSettle();
    await revealByDragging(tester, find.text('默认锁屏显示'), settingsScroll);
    await tester.tap(find.text('默认锁屏显示')); await tester.pumpAndSettle();
    await tester.tap(find.text('不在锁屏显示').last); await tester.pumpAndSettle();
    expect(defaults['presentation'], 'drawer'); expect(defaults['lockscreen'], 'hidden');
    await tester.tap(find.byTooltip('关闭设置分类')); await tester.pumpAndSettle();
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
      {'id': 'style-a', 'name': '横幅提醒 · 振动三次', 'count': 8, 'isDefault': true, 'importance': 4,
        'vibrationMismatch': true, 'actualVibration': '系统已记录：1 段振动（硬件效果请实测）'},
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
    await tester.tap(find.text('帮助与诊断')); await tester.pumpAndSettle();
    final settingsScroll = find.byType(Scrollable).last;
    await revealByDragging(tester, find.text('检查系统通知与锁屏设置'), settingsScroll);
    expect(find.text('检查系统通知与锁屏设置'), findsOneWidget);
    expect(find.text('检查通知横幅与锁屏显示'), findsNothing);
    await revealByDragging(tester, find.text('通知样式（2种）'), settingsScroll);
    expect(find.text('横幅提醒 · 振动三次'), findsNothing);
    await tester.tap(find.text('通知样式（2种）')); await tester.pumpAndSettle();
    await revealByDragging(tester, find.text('仅通知栏 · 不振动'), settingsScroll);
    expect(find.textContaining('关联 8 条备忘'), findsOneWidget);
    expect(find.textContaining('系统已记录：1 段振动'), findsOneWidget);
    expect(find.textContaining('关联 2 条备忘'), findsOneWidget);
    await tester.tap(find.text('仅通知栏 · 不振动')); await tester.pumpAndSettle();
    expect(opened, 'style-b');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('vibration preview does not choose or save a different mode', (tester) async {
    String? previewed, selected;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native, (call) async { if (call.method == 'previewVibration') { previewed = call.arguments as String; } return null; });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { selected = await chooseVibration(context, 'once'); }, child: const Text('打开振动模式'))))));
    await tester.tap(find.text('打开振动模式')); await tester.pumpAndSettle();
    expect(find.textContaining('次数由系统决定'), findsOneWidget);
    await tester.tap(find.byTooltip('试振振动三次')); await tester.pumpAndSettle();
    expect(previewed, 'three'); expect(selected, isNull); expect(find.text('振动模式'), findsOneWidget);
    await tester.tap(find.text('振动两次')); await tester.pumpAndSettle();
    expect(selected, 'twice'); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('reliability switch persists separately and exports diagnostics rather than backup', (tester) async {
    var reliable = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call.method);
      if (call.method == 'getState') { return jsonEncode({'reminders': [], 'defaults': {}, 'status': {
        'notifications': true, 'exact': true, 'reliableMode': reliable, 'guardianRunning': false, 'pending': {'count': 0}}}); }
      if (call.method == 'reliableMode') { reliable = call.arguments as bool; }
      if (call.method == 'exportDiagnostics') { return true; }
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
    await tester.tap(find.text('后台与权限')); await tester.pumpAndSettle();
    final scroll = find.byType(Scrollable).last;
    await revealByDragging(tester, find.text('可靠提醒模式'), scroll);
    await tester.tap(find.text('可靠提醒模式')); await tester.pumpAndSettle();
    expect(reliable, isFalse);
    expect(find.text('可靠模式已关闭，仍保留系统闹钟'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭设置分类')); await tester.pumpAndSettle();
    await tester.tap(find.text('帮助与诊断')); await tester.pumpAndSettle();
    await revealByDragging(tester, find.text('导出提醒诊断'), find.byType(Scrollable).last);
    await tester.tap(find.text('导出提醒诊断')); await tester.pumpAndSettle();
    expect(calls, contains('exportDiagnostics'));
    expect(calls, isNot(contains('exportBackup'))); expect(calls, isNot(contains('save')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('cold entry retries voice readiness after inactive-to-resumed transition', (tester) async {
    var readinessChecks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {}});
      if (call.method == 'voiceEntryAllowed') { readinessChecks++; return false; }
      if (call.method == 'initialReminderId') return 0;
      return null;
    });
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    expect(readinessChecks, greaterThanOrEqualTo(1));
    final before = readinessChecks;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(readinessChecks, greaterThan(before));
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('external returns start home prelisten from every previously selected tab', (tester) async {
    var allowed = false, checks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {}});
      if (call.method == 'voiceEntryAllowed') { checks++; return allowed; }
      if (call.method == 'initialReminderId') return 0;
      return null; // Intentionally fail model preparation; this test concerns entry routing.
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    for (final label in ['日历', '语音', '设置']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pumpAndSettle();
      final before = checks; allowed = true;
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
        AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(checks, greaterThan(before));
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
      expect(tester.takeException(), isNull);
      allowed = false;
    }
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('a late foreground check cannot override a manual voice tab selection', (tester) async {
    final readiness = Completer<bool>(); var checks = 0, microphones = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {}});
      if (call.method == 'voiceEntryAllowed') { checks++; return readiness.future; }
      if (call.method == 'initialReminderId') return 0;
      if (call.method == 'startRecording') microphones++;
      return null;
    });
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle(); expect(checks, 1);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('语音')));
    await tester.pumpAndSettle(); readiness.complete(true); await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);
    expect(microphones, 0); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('notification entry is quiet but the next ordinary foreground return can prelisten', (tester) async {
    var checks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {}});
      if (call.method == 'voiceEntryAllowed') { checks++; return false; }
      if (call.method == 'initialReminderId') return 7;
      return null;
    });
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle(); expect(checks, 0);
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
      AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle(); expect(checks, 1);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('internal tab switches and repeated home taps never restart command prelisten', (tester) async {
    var checks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {}});
      if (call.method == 'voiceEntryAllowed') { checks++; return false; }
      if (call.method == 'initialReminderId') return 0;
      return null;
    });
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('日历'))); await tester.pumpAndSettle();
    final before = checks;
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('备忘录'))); await tester.pumpAndSettle();
    expect(checks, before);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('备忘录'))); await tester.pumpAndSettle();
    expect(checks, before);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('manual voice tab prewarms without opening a microphone', (tester) async {
    var preparations = 0, microphones = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {'handsFree': false}, 'status': {}});
      if (call.method == 'prepareAsr') preparations++;
      if (call.method == 'startRecording') microphones++;
      if (call.method == 'initialReminderId') return 0;
      return null;
    });
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    expect(preparations, 0);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('语音'))); await tester.pumpAndSettle();
    expect(preparations, 1); expect(microphones, 0); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

  testWidgets('a newer foreground return is retried after an older readiness check completes', (tester) async {
    final first = Completer<bool>(); var checks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {}});
      if (call.method == 'voiceEntryAllowed') { checks++; return checks == 1 ? first.future : false; }
      if (call.method == 'initialReminderId') return 0;
      return null;
    });
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle(); expect(checks, 1);
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
      AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle(); first.complete(false); await tester.pumpAndSettle();
    expect(checks, 2); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });

}
