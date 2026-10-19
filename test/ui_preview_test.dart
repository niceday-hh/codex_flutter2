import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/voice_flow.dart';
import 'package:timed_memo/voice_page.dart';
import 'voice_flow_test.dart' show FakeCapture, FakeStore;

const previewKey = ValueKey('ui-preview');
final previewsEnabled = Platform.environment['MEMO_UI_PREVIEWS'] == '1';

Future<void> capture(WidgetTester tester, String name) async {
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
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  testWidgets('render actual settings overview and voice input sheet', (tester) async {
    tester.view.devicePixelRatio = 2; tester.view.physicalSize = const Size(786, 1704);
    addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('memo/native'), (call) async => call.method == 'getState'
        ? jsonEncode({'reminders': [], 'defaults': {'handsFree': true}, 'status': {'version': '0.9.2', 'notifications': true, 'exact': true}}) : null);
    await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp())); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('设置'))); await tester.pumpAndSettle();
    await capture(tester, 'settings-overview');
    await tester.tap(find.text('语音录入')); await tester.pumpAndSettle();
    await capture(tester, 'settings-voice-input');
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
    await tester.pumpWidget(RepaintBoundary(key: previewKey, child: MaterialApp(theme: ThemeData(useMaterial3: true,
      fontFamily: 'Roboto', colorScheme: ColorScheme.fromSeed(seedColor: purple), scaffoldBackgroundColor: canvas,
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))))),
      home: Scaffold(body: VoicePage(flow: flow)))));
    unawaited(showDialog<void>(context: tester.element(find.byType(Scaffold)), barrierColor: ink.withValues(alpha: .20),
      builder: (_) => VoiceConfirmation(flow: flow, onEdit: () async {})));
    await capture(tester, 'voice-confirmation');
    await tester.pumpWidget(const SizedBox()); flow.dispose(); await tester.pump();
  }, skip: !previewsEnabled);
}
