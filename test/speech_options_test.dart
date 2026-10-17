import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/speech_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async => null);
  });
  testWidgets('lockscreen speech privacy can be disabled independently', (tester) async {
    final r = Reminder(speechMode: 'on', lockscreen: 'private');
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpeechOptions(reminder: r, defaults: const {}, onChanged: () async {}))));
    await tester.tap(find.text('锁屏时隐藏播报正文')); await tester.pumpAndSettle();
    expect(r.speechHideLocked, isFalse); expect(r.lockscreen, 'private');
    expect(find.textContaining('锁屏时也允许朗读完整内容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('all actual voice IDs can be searched and selected', (tester) async {
    final r = Reminder();
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpeechOptions(reminder: r, defaults: const {}, onChanged: () async {}))));
    await tester.tap(find.text('播报音色')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '803'); await tester.pumpAndSettle();
    expect(find.text(speechVoiceLabel('803')), findsOneWidget);
    await tester.tap(find.text(speechVoiceLabel('803'))); await tester.pumpAndSettle();
    expect(r.speechVoice, '803');
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('random picker selects within the selected group and search', (tester) async {
    final r = Reminder(speechRandom: true, speechRandomLanguage: 'ja', speechRandomGender: 'female');
    await tester.binding.setSurfaceSize(const Size(393, 1200));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      SpeechOptions(reminder: r, defaults: const {}, onChanged: () async {})))));
    await tester.tap(find.text('播报音色')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '303'); await tester.pumpAndSettle();
    expect(find.text(speechVoiceLabel('303')), findsOneWidget);
    await tester.tap(find.text('随机挑一个')); await tester.pumpAndSettle();
    expect(r.speechVoice, '303');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
