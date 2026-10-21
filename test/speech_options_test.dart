import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/speech_options.dart';
import 'package:timed_memo/speech_variation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async => null);
  });
  testWidgets('slower synthesis rates can be selected without changing the existing rate', (tester) async {
    double? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(
      onPressed: () async { selected = await chooseSpeechRate(c, .8, allowDefault: false); }, child: const Text('打开语速'))))));
    await tester.tap(find.text('打开语速')); await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, .8); expect(slider.min, .5); expect(slider.max, 1.3);
    slider.onChanged!(.5); await tester.pump();
    await tester.tap(find.text('使用此语速')); await tester.pumpAndSettle();
    expect(selected, .5);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  testWidgets('advanced noise controls preserve defaults, allow overrides and round-trip values', (tester) async {
    SpeechVariation? selected;
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () async {
      selected = await chooseSpeechVariation(c, noise: 0, noiseW: 0, allowDefault: true, defaultNoise: .6, defaultNoiseW: .668);
    }, child: const Text('高级参数'))))));
    await tester.tap(find.text('高级参数')); await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byKey(const ValueKey('speech-noise-w'))).value, .668);
    expect(tester.widget<Slider>(find.byKey(const ValueKey('speech-noise'))).onChanged, isNull);
    await tester.tap(find.text('跟随默认参数')); await tester.pumpAndSettle();
    tester.widget<Slider>(find.byKey(const ValueKey('speech-noise'))).onChanged!(.4);
    tester.widget<Slider>(find.byKey(const ValueKey('speech-noise-w'))).onChanged!(.5);
    await tester.pump(); await tester.tap(find.text('使用这些参数')); await tester.pumpAndSettle();
    expect(selected!.noise, .4); expect(selected!.noiseW, .5);
    final copy = Reminder.fromJson(Reminder(speechNoiseScale: .4, speechNoiseScaleW: .5, speechSeed: 123).toJson());
    expect(copy.speechNoiseScale, .4); expect(copy.speechNoiseScaleW, .5); expect(copy.speechSeed, 123);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
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
    expect(find.text('选择播报音色'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '303'); await tester.pumpAndSettle();
    expect(find.text(speechVoiceLabel('303')), findsOneWidget);
    await tester.tap(find.text('随机挑一个')); await tester.pumpAndSettle();
    expect(r.speechVoice, '303');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
