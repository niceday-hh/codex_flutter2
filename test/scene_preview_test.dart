import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/scene_templates.dart';
import 'package:timed_memo/task_batch.dart';
import 'package:timed_memo/widgets/memo_time_sheet.dart';

void main() {
  final saved = <Map<String, dynamic>>[];
  var nextId = 1;
  setUp(() {
    saved.clear(); nextId = 1;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return '{"reminders":[],"defaults":{},"status":{}}';
      if (call.method == 'getSceneTemplates') return '[]';
      if (call.method == 'reserveReminderId') return nextId++;
      if (call.method == 'save') saved.add(jsonDecode(call.arguments as String) as Map<String, dynamic>);
      return null;
    });
  });
  Future<void> phone(WidgetTester tester, {Size size = const Size(393, 852)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
  }
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder); await tester.pumpAndSettle();
    await tester.tap(finder); await tester.pumpAndSettle();
  }
  Future<DateTime> start(WidgetTester tester, String shift) async {
    await tap(tester, find.byKey(const ValueKey('scene-start-time')));
    expect(find.text('设置场景开始时间'), findsOneWidget);
    final initial = tester.widget<MemoTimeSheet>(find.byType(MemoTimeSheet)).initial;
    await tap(tester, find.text(shift));
    await tap(tester, find.text('确定'));
    return initial.add(Duration(minutes: shift == '+15 分钟' ? 15 : 30));
  }
  testWidgets('real template preview opens relative arrangements before any time picker or write', (tester) async {
    await phone(tester);
    await tap(tester, find.text('场景模板'));
    await tap(tester, find.text('预览 3 条提醒'));
    expect(find.byType(TaskBatchPage), findsOneWidget);
    expect(find.byType(MemoTimeSheet), findsNothing);
    expect(find.text('开始时'), findsOneWidget); expect(find.text('30 分钟后'), findsOneWidget);
    expect(find.text('40 分钟后'), findsOneWidget); expect(find.text('未设置 · 选择时间'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '请先选择开始时间')).onPressed, isNull);
    expect(saved, isEmpty);
    await tap(tester, find.byKey(const ValueKey('scene-start-time')));
    await tap(tester, find.descendant(of: find.byType(MemoTimeSheet), matching: find.text('取消')));
    expect(find.byType(TaskBatchPage), findsOneWidget);
    expect(find.text('未设置 · 选择时间'), findsOneWidget); expect(saved, isEmpty);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('choosing a start creates the selected scene at exact offsets only after confirmation', (tester) async {
    await phone(tester);
    await tap(tester, find.text('场景模板')); await tap(tester, find.text('预览 3 条提醒'));
    final chosen = await start(tester, '+15 分钟');
    expect(saved, isEmpty);
    await tap(tester, find.text('创建 3 条提醒'));
    expect(saved.map((r) => r['text']), ['阅读', '休息一下', '复习与整理']);
    expect(saved.map((r) => Reminder.fromJson(r).date),
      [chosen, chosen.add(const Duration(minutes: 30)), chosen.add(const Duration(minutes: 40))]);
    expect(find.byType(TaskBatchPage), findsNothing);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('changing scene start preserves individual time edits and exclusions', (tester) async {
    await phone(tester);
    final context = tester.element(find.text('场景模板'));
    final scene = builtInScenes.first;
    final manual = DateTime(2040, 1, 1, 11, 30);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskBatchPage(
      drafts: scene.instantiate(DateTime(2000), MemoStore()), source: scene.name, store: MemoStore(),
      sceneName: scene.name, sceneOffsets: const [0, 30, 40],
      edit: (_, r) async => r..date = manual..text = '单独安排的阅读')));
    await tester.pumpAndSettle();
    await start(tester, '+15 分钟');
    await tap(tester, find.byTooltip('编辑第 1 条'));
    expect(find.text('时间已单独调整'), findsOneWidget); expect(saved, isEmpty);
    final revised = await start(tester, '+30 分钟');
    await tap(tester, find.byType(Checkbox).last);
    await tap(tester, find.text('创建 2 条提醒'));
    expect(saved.map((r) => r['text']), ['单独安排的阅读', '休息一下']);
    expect(saved.map((r) => Reminder.fromJson(r).date), [manual, revised.add(const Duration(minutes: 30))]);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('relative scene preview remains reachable at large text on a short phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
      home: TaskBatchPage(drafts: builtInScenes.first.instantiate(DateTime(2000), MemoStore()),
        source: '晚间学习', sceneName: '晚间学习', sceneOffsets: const [0, 30, 40], store: MemoStore(), edit: (_, r) async => r)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tap(tester, find.byKey(const ValueKey('scene-start-time')));
    expect(find.text('设置场景开始时间'), findsOneWidget); expect(tester.takeException(), isNull);
    await tap(tester, find.descendant(of: find.byType(MemoTimeSheet), matching: find.text('取消')));
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
