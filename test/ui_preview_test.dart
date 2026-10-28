import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/settings_page.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/voice_flow.dart';
import 'package:timed_memo/voice_page.dart';
import 'voice_flow_test.dart' show FakeCapture, FakeStore;

const previewKey = ValueKey('ui-preview');
final previewsEnabled = Platform.environment['MEMO_UI_PREVIEWS'] == '1';

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(previewKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('ui-previews/$name.png'); file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List()); image.dispose();
  });
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    if (!previewsEnabled) return;
    final bytes = File(Platform.environment['MEMO_PREVIEW_FONT']!).readAsBytesSync();
    // The test harness paints unstyled text with its own fallback font, which
    // has no CJK glyphs. Register the preview font under every family name the
    // engine may resolve so previews match the real device.
    for (final family in ['Roboto', 'Ahem', 'FlutterTest']) {
      final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('render actual settings overview and voice input sheet', (tester) async {
    tester.view.devicePixelRatio = 2; tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async => call.method == 'getState'
        ? jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {'version': '0.9.3', 'notifications': true, 'exact': true}}) : null);
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp())); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
    await capture(tester, 'settings-overview');
    await tester.tap(find.text('语音录入')); await tester.pumpAndSettle();
    await capture(tester, 'settings-voice-input');
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  }, skip: !previewsEnabled);
  testWidgets('render child search, preview and feedback in the open settings sheet', (tester) async {
    tester.view.devicePixelRatio = 2; tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async {
        if (call.method == 'getState') return jsonEncode({'reminders': [], 'defaults': {}, 'status': {'version': '0.9.3', 'notifications': true, 'exact': true}});
        if (call.method == 'requestNotifications') return true;
        if (call.method == 'testReminder') return 1;
        return null;
      });
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp())); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('settings-search')), '15秒'); await tester.pumpAndSettle();
    await capture(tester, 'settings-search-results');
    await tester.tap(find.byKey(const ValueKey('settings-result-test'))); await tester.pumpAndSettle();
    await capture(tester, 'settings-search-preview');
    await tester.tap(find.text('前往设置')); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(SettingsSheet), matching: find.text('15秒后发送测试提醒'))); await tester.pumpAndSettle();
    expect(find.text('测试提醒已设置，请返回桌面等待15秒'), findsOneWidget);
    await capture(tester, 'settings-test-feedback');
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  }, skip: !previewsEnabled);
  testWidgets('render saved reminder detail, audio actions and inline export success', (tester) async {
    tester.view.devicePixelRatio = 2; tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    final row = Reminder(id: 7, text: '喝水，休息一下眼睛。\n为明天的会议准备好资料。', date: DateTime(2030, 1, 1, 22, 30),
      speechMode: 'on', speechVoice: '228', speechRate: .8, speechState: 'ready');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'getState') {
        return jsonEncode({'reminders': [row.toJson()..['speechState'] = 'ready'],
          'defaults': {}, 'status': {'version': '0.9.5', 'notifications': true, 'exact': true}});
      }
      if (call.method == 'reminderAudioJob' || call.method == 'candidateReminderAudio') {
        return jsonEncode({'lease': 'preview-lease', 'ready': true, 'key': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.wav', 'reminderId': 7});
      }
      if (call.method == 'reminderAudioReady' || call.method == 'exportReminderAudio') return true;
      return null;
    });
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp())); await tester.pumpAndSettle();
    await tester.tap(find.text(row.text).first); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存音频')); await tester.pumpAndSettle();
    await capture(tester, 'reminder-audio-actions');
    await tester.tap(find.text('保存音频')); await tester.pumpAndSettle();
    expect(find.text('音频已保存到所选位置。'), findsOneWidget);
    await capture(tester, 'reminder-audio-saved');
    await tester.tap(find.text('换一版')); await tester.pumpAndSettle();
    expect(find.text('使用此版本'), findsOneWidget,
      reason: tester.widget<Text>(find.byKey(const ValueKey('reminder-audio-feedback'))).data);
    await tester.ensureVisible(find.text('使用此版本')); await tester.pumpAndSettle();
    await capture(tester, 'reminder-audio-candidate');
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  }, skip: !previewsEnabled);
  testWidgets('render advanced voice settings with both noise controls', (tester) async {
    tester.view.devicePixelRatio = 2; tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async => call.method == 'getState'
      ? jsonEncode({'reminders': [], 'defaults': {}, 'status': {'version': '0.9.6', 'notifications': true, 'exact': true}}) : null);
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp())); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
    await tester.tap(find.text('语音播报')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('高级语音设置')); await tester.pumpAndSettle();
    await tester.tap(find.text('高级语音设置')); await tester.pumpAndSettle();
    await capture(tester, 'speech-advanced-noise');
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  }, skip: !previewsEnabled);
  testWidgets('render actual voice confirmation with parsed retry settings', (tester) async {
    tester.view.devicePixelRatio = 2; tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    final flow = VoiceFlow(capture: FakeCapture(), store: FakeStore(), clock: () => DateTime(2030, 1, 1, 22),
      openVoicePage: () {}, onSaved: () async {});
    await flow.reviewText('今天22:30提醒我喝水，休息一下眼睛，每隔3分钟提醒，总共提醒5次，开启语音播报');
    flow.secondsLeft = 18;
    await tester.pumpWidget(RepaintBoundary(key: previewKey, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(useMaterial3: true,
      fontFamily: 'Roboto', colorScheme: ColorScheme.fromSeed(seedColor: purple), scaffoldBackgroundColor: canvas,
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))))),
      home: Scaffold(body: VoicePage(flow: flow)))));
    unawaited(showDialog<void>(context: tester.element(find.byType(Scaffold)), barrierColor: ink.withValues(alpha: .20),
      builder: (_) => VoiceConfirmation(flow: flow, onEdit: () async {})));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(VoiceConfirmation), findsOneWidget);
    expect(find.text('共 5 次（含首次）'), findsOneWidget);
    await capture(tester, 'voice-confirmation');
    await tester.pumpWidget(const SizedBox()); flow.dispose(); await tester.pump();
  }, skip: !previewsEnabled);
}
