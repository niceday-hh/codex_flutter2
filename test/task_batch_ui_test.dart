import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/appearance.dart';
import 'package:timed_memo/design_tokens.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/task_batch.dart';
import 'package:timed_memo/voice_parser.dart';
import 'ui_preview_test.dart' show capture, previewKey, previewsEnabled;

void main() {
  setUpAll(() async {
    if (!previewsEnabled) return;
    final bytes = File(Platform.environment['MEMO_PREVIEW_FONT']!).readAsBytesSync();
    for (final family in ['Roboto', 'Ahem', 'FlutterTest']) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MemoSerif')..addFont(rootBundle.load('assets/fonts/MemoSerif-Regular.otf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final accent in MemoAccent.values) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('scenes and batch follow ${accent.name}/${mode.name} at 320dp', (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(() => appearance.value = Appearance.defaults);
        appearance.value = Appearance(mode: mode, accent: accent);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
          if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {}});
          if (call.method == 'getSceneTemplates') return '[]';
          return null;
        });
        await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp())); await tester.pumpAndSettle();
        await tester.tap(find.text('场景模板')); await tester.pumpAndSettle();
        expect(find.text('晚间学习'), findsOneWidget);
        final sceneContext = tester.element(find.text('晚间学习'));
        expect(MemoTokens.of(sceneContext).colors.brand700,
          MemoTokens.forAccent(accent, mode == ThemeMode.dark ? Brightness.dark : Brightness.light).colors.brand700);
        expect(tester.takeException(), isNull);
        if (previewsEnabled) await capture(tester, 'scenes-${accent.name}-${mode.name}');
        final at = DateTime.now().add(const Duration(days: 1));
        Navigator.of(sceneContext).push(MaterialPageRoute<void>(builder: (_) => TaskBatchPage(
          drafts: [for (var i = 0; i < 3; i++) ParsedVoice(Reminder(text: ['起床', '出门', '读书'][i], date: at.add(Duration(hours: i))), true, null, at)],
          source: '明天七点起床，八点出门，晚上九点读书', store: MemoStore(), edit: (_, r) async => r)));
        await tester.pumpAndSettle();
        expect(find.text('核对 3 条提醒'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (previewsEnabled) await capture(tester, 'batch-${accent.name}-${mode.name}');
        await tester.pumpWidget(const SizedBox()); await tester.pump();
      });
    }
  }
  testWidgets('partial save retries only remaining rows and never saves when merely editing', (tester) async {
    final counts = <String, int>{}; var fail = true; var nextId = 1;
    final ids = <String, List<int>>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return '{"reminders":[],"defaults":{},"status":{}}';
      if (call.method == 'reserveReminderId') return nextId++;
      if (call.method == 'save') {
        final name = jsonDecode(call.arguments as String)['text'] as String;
        (ids[name] ??= []).add(jsonDecode(call.arguments as String)['id'] as int);
        counts[name] = (counts[name] ?? 0) + 1;
        if (name == '第二条' && fail) throw PlatformException(code: 'TEST', message: '临时失败');
      }
      return null;
    });
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    final context = tester.element(find.text('场景模板'));
    final at = DateTime.now().add(const Duration(days: 1));
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskBatchPage(
      drafts: [for (final name in ['第一条', '第二条']) ParsedVoice(Reminder(text: name, date: at), true, null, at)],
      source: '两条提醒', store: MemoStore(), edit: (_, r) async => r)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑第 1 条')); await tester.pumpAndSettle(); expect(counts, isEmpty);
    await tester.ensureVisible(find.text('创建 2 条提醒')); await tester.tap(find.text('创建 2 条提醒')); await tester.pumpAndSettle();
    expect(counts, {'第一条': 1, '第二条': 1});
    fail = false;
    await tester.ensureVisible(find.text('创建 1 条提醒')); await tester.tap(find.text('创建 1 条提醒')); await tester.pumpAndSettle();
    expect(counts, {'第一条': 1, '第二条': 2});
    expect(ids['第二条'], [2, 2]); expect(nextId, 3);
    expect(find.text('核对 2 条提醒'), findsNothing);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
