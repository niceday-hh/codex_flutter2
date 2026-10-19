import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/voice_flow.dart';
import 'package:timed_memo/voice_page.dart';
import 'voice_flow_test.dart' show FakeCapture, FakeStore;
void main() {
  testWidgets('confirmation is a visual dialog and repeated button presses cannot double save', (tester) async {
    final capture = FakeCapture(), store = FakeStore();
    final flow = VoiceFlow(capture: capture, store: store, clock: () => DateTime(2030),
      openVoicePage: () {}, onSaved: () async {});
    await flow.reviewText('五分钟后提醒我喝水');
    await tester.binding.setSurfaceSize(const Size(393, 852));
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
