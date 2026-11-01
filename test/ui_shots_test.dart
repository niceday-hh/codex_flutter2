// Screenshot harness, not a regression test. Run with:
//
//   MEMO_UI_PREVIEWS=1 \
//   MEMO_PREVIEW_FONT=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
//   flutter test test/ui_shots_test.dart
//
// Output lands in `ui-shots/`. Skipped in a normal run so CI never depends on
// a system font.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/appearance.dart';
import 'package:timed_memo/design_tokens.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/widgets/memo_tab_bar.dart';

const previewKey = ValueKey('ui-preview');
final previewsEnabled = Platform.environment['MEMO_UI_PREVIEWS'] == '1';

DateTime at(int dayOffset, int hour, int minute) {
  final n = DateTime.now();
  final d = DateTime(n.year, n.month, n.day).add(Duration(days: dayOffset));
  return DateTime(d.year, d.month, d.day, hour, minute);
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(previewKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('ui-shots/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    if (!previewsEnabled) return;
    final sans = File(Platform.environment['MEMO_PREVIEW_FONT']!).readAsBytesSync();
    for (final family in ['Roboto', 'Ahem', 'FlutterTest']) {
      final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(sans)));
      await loader.load();
    }
    final serif = File('assets/fonts/MemoSerif-Regular.otf').readAsBytesSync();
    await (FontLoader('MemoSerif')..addFont(Future.value(ByteData.sublistView(serif)))).load();
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('shoot the home list and the detail sheet', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => appearance.value = Appearance.defaults);

    final rows = [
      // Tomorrow morning, not a fixed hour today: the hero now prints the
      // distance to the next reminder, and a fixture pinned to 15:00 turns
      // that pill into "已过 8 小时" whenever the shots are taken in the
      // evening. A clean future span is the thing being documented.
      Reminder(id: 1, text: '交物业费', date: at(1, 9, 0)).toJson(),
      // Four different states in one screen, so the shot proves the chips read
      // apart from each other instead of four grey words in a row.
      Reminder(id: 2, text: '预约儿科挂号', date: at(1, 11, 30), repeat: 'daily').toJson()
        ..['speechState'] = 'preparing',
      Reminder(id: 3, text: '给妈妈打个电话', date: at(1, 14, 0),
        repeat: 'weekly', days: [1, 5]).toJson()..['speechState'] = 'ready',
      Reminder(id: 4, text: '妈妈复查血压，记得带上上次的化验单', date: at(1, 18, 30),
        repeat: 'daily').toJson()..['speechState'] = 'missing',
      Reminder(id: 5, text: '交房租', date: at(1, 21, 30)).toJson()..['speechState'] = 'error',
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native,
      (call) async => call.method == 'getState'
        ? jsonEncode({
            'reminders': rows,
            'defaults': {},
            'status': {'version': '0.9.18', 'notifications': true, 'exact': true},
          })
        : null,
    );

    appearance.value = const Appearance(mode: ThemeMode.dark, accent: MemoAccent.violet);
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp()));
    await tester.pumpAndSettle();
    await capture(tester, 'home-dark-violet');

    appearance.value = const Appearance(mode: ThemeMode.light, accent: MemoAccent.violet);
    await tester.pumpAndSettle();
    await capture(tester, 'home-light-violet');

    appearance.value = const Appearance(mode: ThemeMode.dark, accent: MemoAccent.teal);
    await tester.pumpAndSettle();
    await capture(tester, 'home-dark-teal');

    // Batch mode on the home page: the card steps aside, every reminder turns
    // into a tickable row, and the bar names the count.
    await tester.longPress(find.text('预约儿科挂号'));
    await tester.pumpAndSettle();
    await capture(tester, 'home-select-teal');
    await tester.tap(find.byTooltip('取消选择'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('妈妈复查血压，记得带上上次的化验单').last);
    await tester.pumpAndSettle();
    await capture(tester, 'detail-dark-teal');

    // Close the sheet before switching: its backgroundColor is captured when
    // the route is pushed, so a live theme swap would leave a dark sheet with
    // light-theme contents on it — a state the app cannot actually reach.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    appearance.value = const Appearance(mode: ThemeMode.light, accent: MemoAccent.violet);
    await tester.pumpAndSettle();
    await tester.tap(find.text('妈妈复查血压，记得带上上次的化验单').last);
    await tester.pumpAndSettle();
    await capture(tester, 'detail-light-violet');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }, skip: !previewsEnabled);

  testWidgets('shoot the single-reminder menu', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => appearance.value = Appearance.defaults);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native,
      (call) async => call.method == 'getState'
        ? jsonEncode({
            'reminders': [Reminder(id: 1, text: '交物业费', date: at(1, 9, 0)).toJson()],
            'defaults': {},
            'status': {'version': '0.9.18', 'notifications': true, 'exact': true},
          })
        : null,
    );

    appearance.value = const Appearance(mode: ThemeMode.dark, accent: MemoAccent.teal);
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp()));
    await tester.pumpAndSettle();
    // The whole point of the release: a day with one reminder still has an
    // archive and a delete, and they live on the card.
    // The same task now has two exits — the card's ⋯ and its row's; open the
    // card's, which is the one this shot is about.
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    await capture(tester, 'single-menu-dark');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }, skip: !previewsEnabled);

  testWidgets('shoot the history batch bar', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => appearance.value = Appearance.defaults);

    final ago = DateTime.now().millisecondsSinceEpoch - 2 * 86400000;
    final rows = [
      Reminder(id: 1, text: '交物业费', date: at(0, 15, 0)).toJson(),
      Reminder(id: 2, text: '修阳台灯', date: at(-2, 20, 10), enabled: false, completed: true).toJson()
        ..['completed'] = true ..['archived'] = true ..['archivedAt'] = ago,
      Reminder(id: 3, text: '换季衣服收纳', date: at(-2, 9, 30), enabled: false, completed: true).toJson()
        ..['completed'] = true ..['archived'] = true ..['archivedAt'] = ago - 3600000,
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native,
      (call) async => call.method == 'getState'
        ? jsonEncode({
            'reminders': rows,
            'defaults': {},
            'status': {'version': '0.9.18', 'notifications': true, 'exact': true},
          })
        : null,
    );

    appearance.value = const Appearance(mode: ThemeMode.dark, accent: MemoAccent.teal);
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史任务'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('修阳台灯'));
    await tester.pumpAndSettle();
    await capture(tester, 'history-select-teal');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }, skip: !previewsEnabled);

  testWidgets('shoot the tab bar, calendar, settings and history filters', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => appearance.value = Appearance.defaults);

    final ago = DateTime.now().millisecondsSinceEpoch - 86400000;
    final rows = [
      Reminder(id: 1, text: '交物业费', date: at(0, 15, 0)).toJson(),
      Reminder(id: 2, text: '预约儿科挂号', date: at(0, 18, 30), repeat: 'daily').toJson()
        ..['speechState'] = 'preparing',
      Reminder(id: 3, text: '给妈妈打个电话', date: at(0, 21, 0), repeat: 'weekly', days: [1, 5]).toJson()
        ..['speechState'] = 'ready',
      Reminder(id: 4, text: '修阳台灯', date: at(-1, 20, 10), enabled: false, completed: true).toJson()
        ..['completed'] = true ..['archived'] = true ..['archivedAt'] = ago,
      // A repeat in history shows the other verb: 开启 re-arms the rule,
      // while the one-shot above can only be edited.
      Reminder(id: 5, text: '晨跑', date: at(-1, 7, 0), repeat: 'daily', enabled: false, completed: true).toJson()
        ..['completed'] = true ..['archived'] = true ..['archivedAt'] = ago - 7200000,
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native,
      (call) async => call.method == 'getState'
        ? jsonEncode({'reminders': rows, 'defaults': {},
            'status': {'version': '0.9.18', 'notifications': true, 'exact': true}})
        : null,
    );

    appearance.value = const Appearance(mode: ThemeMode.light, accent: MemoAccent.violet);
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp()));
    await tester.pumpAndSettle();
    await capture(tester, 'tabs-home-light');

    await tester.tap(find.descendant(of: find.byType(MemoTabBar), matching: find.text('日历')));
    await tester.pumpAndSettle();
    await capture(tester, 'tabs-calendar-light');

    await tester.tap(find.descendant(of: find.byType(MemoTabBar), matching: find.text('设置')));
    await tester.pumpAndSettle();
    await capture(tester, 'tabs-settings-light');

    await tester.tap(find.descendant(of: find.byType(MemoTabBar), matching: find.text('备忘录')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史任务'));
    await tester.pumpAndSettle();
    await capture(tester, 'history-filter-light');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }, skip: !previewsEnabled);
}
