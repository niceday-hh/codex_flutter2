import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/task_batch.dart';
import 'package:timed_memo/voice_parser.dart';
import 'package:timed_memo/speech_options.dart';

void main() {
  final saved = <Map<String, dynamic>>[];
  setUp(() {
    saved.clear(); var id = 100;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') return '{"reminders":[],"defaults":{},"status":{}}';
      if (call.method == 'reserveReminderId') return id++;
      if (call.method == 'save') saved.add(jsonDecode(call.arguments as String) as Map<String, dynamic>);
      return null;
    });
  });
  Future<void> open(WidgetTester tester, String source, {EditBatchDraft? edit}) async {
    await tester.binding.setSurfaceSize(const Size(393, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
    final context = tester.element(find.text('场景模板'));
    final at = DateTime.now().add(const Duration(days: 1));
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskBatchPage(
      source: source, voiceSource: true, store: MemoStore(),
      drafts: parseVoiceBatch(source, now: at, defaults: () => Reminder()), edit: edit ?? (_, r) async => r)));
    await tester.pumpAndSettle();
  }
  for (final split in [false, true]) {
    testWidgets('ambiguous boundaries block save until explicit ${split ? "split" : "keep"}', (tester) async {
      await open(tester, '明天九点提醒我起床十点学习');
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '创建 1 条提醒')).onPressed, isNull);
      await tester.tap(find.text('1 条已选，1 条待核对')); await tester.pumpAndSettle();
      expect(find.text('拆成两条').hitTestable(), findsOneWidget); expect(saved, isEmpty);
      await tester.ensureVisible(find.text(split ? '拆成两条' : '保留一条'));
      await tester.tap(find.text(split ? '拆成两条' : '保留一条')); await tester.pumpAndSettle();
      await tester.tap(find.text('创建 ${split ? 2 : 1} 条提醒')); await tester.pumpAndSettle();
      expect(saved.map((r) => r['text']), split ? ['起床', '学习'] : ['起床十点学习']);
      await tester.pumpWidget(const SizedBox()); await tester.pump();
    });
  }
  testWidgets('review shortcut locates an offscreen ambiguity and respects reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await open(tester, '明天九点提醒我起床，下一条十点提醒我读书，下一条十一点提醒我出门十二点吃饭');
    await tester.binding.setSurfaceSize(const Size(320, 480));
    await tester.pumpAndSettle();
    final shortcut = find.text('3 条已选，1 条待核对');
    await tester.tap(shortcut); await tester.pumpAndSettle();
    expect(find.text('拆成两条').hitTestable(), findsOneWidget);
    await tester.tap(find.text('拆成两条')); await tester.pump();
    expect(find.text('核对 4 条提醒'), findsOneWidget);
    expect(find.text('3 条已选，1 条待核对'), findsNothing);
    expect(saved, isEmpty);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('relative reference and merge retain the original second schedule text', (tester) async {
    String? merged;
    await open(tester, '五分钟后提醒我调小火，再过十分钟提醒我关火', edit: (_, r) async { merged = r.text; return r; });
    await tester.ensureVisible(find.text('从上一条计划时间起算')); await tester.tap(find.text('从上一条计划时间起算')); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('第 2 条更多操作')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('与上一条合并并编辑')); await tester.tap(find.text('与上一条合并并编辑')); await tester.pumpAndSettle();
    expect(merged, contains('再过十分钟提醒我关火')); expect(find.text('核对 1 条提醒'), findsOneWidget); expect(saved, isEmpty);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('retry announcement toggle persists on task roundtrip and copies new defaults', (tester) async {
    final r = Reminder(intervalMinutes: 3);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SpeechOptions(
      reminder: r, defaults: const {}, onChanged: () async {}))))); await tester.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, '重提醒追加次数与间隔');
    await tester.ensureVisible(toggle); await tester.tap(toggle); await tester.pumpAndSettle();
    expect(r.speechAnnounceRetry, isTrue); expect(Reminder.fromJson(r.toJson()).speechAnnounceRetry, isTrue);
    final store = MemoStore()..defaults = {'speechAnnounceRetry': true};
    expect(store.draft().speechAnnounceRetry, isTrue); expect(Reminder().speechAnnounceRetry, isFalse);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
