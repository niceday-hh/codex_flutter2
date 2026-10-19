import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/voice_flow.dart';
import 'package:timed_memo/voice_page.dart';
import 'voice_flow_test.dart' show FakeCapture, FakeStore;
void main() {
  for (final size in [const Size(320, 568), const Size(700, 360)]) {
    testWidgets('long confirmation remains scrollable with large text at $size', (tester) async {
      final flow = VoiceFlow(capture: FakeCapture(), store: FakeStore(), clock: () => DateTime(2030),
        openVoicePage: () {}, onSaved: () async {});
      var edits = 0;
      await flow.reviewText('五分钟后提醒我${List.filled(12, '喝水，休息一下眼睛').join('，')}，提醒间隔三分钟，提醒五次');
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)), child: child!),
        home: Scaffold(body: VoiceConfirmation(flow: flow, onEdit: () async { edits++; }))));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('手动编辑')); await tester.pump();
      await tester.tap(find.text('手动编辑')); expect(edits, 1);
      await tester.ensureVisible(find.text('确认创建')); await tester.pump();
      final button = tester.getRect(find.widgetWithText(FilledButton, '确认创建'));
      expect(button.top, greaterThanOrEqualTo(0)); expect(button.bottom, lessThanOrEqualTo(size.height));
      await tester.ensureVisible(find.text('取消')); await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox()); flow.dispose(); await tester.pump();
    });
  }
  testWidgets('uncertain retry count requires editing before creation', (tester) async {
    final store = FakeStore();
    final flow = VoiceFlow(capture: FakeCapture(), store: store, clock: () => DateTime(2030),
      openVoicePage: () {}, onSaved: () async {});
    await flow.reviewText('五分钟后提醒我喝水，再提醒五次');
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VoiceConfirmation(flow: flow, onEdit: () async {}))));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认创建')).onPressed, isNull);
    expect(store.saved, isEmpty);
    await tester.pumpWidget(const SizedBox()); flow.dispose(); await tester.pump();
  });
  testWidgets('confirmation is a visual dialog and repeated button presses cannot double save', (tester) async {
    final capture = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: capture, store: store, clock: () => DateTime(2030),
      openVoicePage: () {}, onSaved: () async {});
    await flow.reviewText('五分钟后提醒我喝水');
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VoiceConfirmation(flow: flow, onEdit: () async {}))));
    expect(find.text('确认提醒'), findsNothing);
    expect(find.text('首次提醒'), findsOneWidget);
    expect(find.text('共 3 次（含首次）'), findsOneWidget);
    expect(find.text('喝水'), findsOneWidget);
    expect(find.textContaining('可说“确认”'), findsOneWidget);
    await tester.tap(find.text('确认创建')); await tester.tap(find.text('确认创建'));
    await tester.pump();
    expect(store.saved.length, 1);
    await tester.pumpWidget(const SizedBox());
    flow.dispose(); await tester.pump();
  });
}
