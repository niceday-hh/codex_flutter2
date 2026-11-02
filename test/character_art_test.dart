import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/appearance.dart';
import 'package:timed_memo/character_art.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';

final screenshots = Platform.environment['MEMO_CHARACTER_PREVIEWS'] == '1';
const boundaryKey = ValueKey('character-preview');

void main() {
  setUpAll(() async {
    if (!screenshots) return;
    final bytes = File('assets/fonts/MemoSerif-Regular.otf').readAsBytesSync();
    for (final family in ['Roboto', 'Ahem', 'FlutterTest', 'MemoSerif']) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test('every runtime mapping names a bundled image with bounded decode dimensions', () {
    final json = jsonDecode(File('assets/character_art/art_catalog.json').readAsStringSync()) as Map<String, dynamic>;
    final catalog = CharacterArtCatalog.fromJson(json);
    expect(catalog.entries.length, 244);
    expect(catalog.entries.values.map((x) => x.asset).toSet().length, 189);
    for (final entry in catalog.entries.values) {
      expect(File(entry.asset).existsSync(), isTrue, reason: entry.asset);
      expect(entry.width * entry.height * 4, lessThan(1200000));
    }
    expect(catalog.entries['46'], isNull);
    expect(catalog.entries['803'], isNull);
    expect(catalog.entries['115']!.isPortrait, isFalse);
    expect(catalog.entries['228']!.isPortrait, isTrue);
  });
  test('art follows effective speech settings and never rerolls a random voice', () {
    final r = Reminder(speechMode: 'inherit');
    expect(reminderArtSpeaker(r, {'speechMode': 'off'}), isNull);
    expect(reminderArtSpeaker(r, {'speechMode': 'on', 'speechVoice': '115'}), '115');
    r.speechRandom = true; r.speechVoice = '228';
    expect(reminderArtSpeaker(r, {'speechMode': 'on', 'speechVoice': '115'}), '228');
    r.resolvedSpeechEnabled = true; r.resolvedSpeechVoice = '115';
    expect(reminderArtSpeaker(r, {}), '115');
    expect(r.toJson().containsKey('resolvedSpeechVoice'), isFalse);
    r.resolvedSpeechEnabled = false;
    expect(reminderArtSpeaker(r, {'speechMode': 'on'}), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final sid in [115, 228, 803]) {
      testWidgets('detail ${mode.name} speaker $sid keeps edit accessible and art decorative', (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(786, 1704);
        addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(() => appearance.value = Appearance.defaults);
        final reminder = Reminder(id: 7, text: '喝水，休息一下眼睛', date: DateTime.now().add(const Duration(hours: 2)),
          speechMode: 'on', speechVoice: '$sid', speechState: 'ready');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
          if (call.method == 'getState') return jsonEncode({'reminders': [reminder.toJson()],
            'defaults': {}, 'status': {'notifications': true, 'exact': true}});
          if (call.method == 'initialReminderId') return 7;
          return null;
        });
        addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, null));
        final catalog = await tester.runAsync(() => CharacterArtCatalog.load());
        appearance.value = Appearance(mode: mode);
        await tester.pumpWidget(const RepaintBoundary(key: boundaryKey, child: MemoApp()));
        await tester.pumpAndSettle();
        final art = catalog!.entries['$sid'];
        if (art != null) {
          final image = tester.widget<Image>(find.byKey(const ValueKey('detail-character-image')));
          await tester.runAsync(() => precacheImage(image.image, tester.element(find.byType(ReminderDetail))));
          await tester.pumpAndSettle();
          final raw = find.descendant(of: find.byKey(const ValueKey('detail-character-image')), matching: find.byType(RawImage));
          expect(tester.renderObject<RenderImage>(raw).image, isNotNull);
          expect(find.ancestor(of: find.byKey(const ValueKey('detail-character-image')), matching: find.byType(IgnorePointer)), findsWidgets);
        } else {
          expect(find.byKey(const ValueKey('detail-character-image')), findsNothing);
        }
        expect(find.text('编辑提醒').hitTestable(), findsOneWidget);
        if (screenshots) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
            final image = await boundary.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('character-ui-previews/${mode.name}-$sid.png');
            file.parent.createSync(recursive: true); file.writeAsBytesSync(png!.buffer.asUint8List()); image.dispose();
          });
        }
        await tester.ensureVisible(find.text('保存音频'));
        await tester.pumpAndSettle();
        expect(find.text('保存音频').hitTestable(), findsOneWidget);
        expect(find.text('编辑提醒').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
      });
    }
  }
  testWidgets('portrait on 320dp with large text keeps every action reachable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, null));
    await tester.runAsync(() => CharacterArtCatalog.load());
    var edited = false;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.6)),
      child: Scaffold(body: ReminderDetail(reminder: Reminder(id: 8,
        text: List.filled(12, '喝水，休息一下眼睛。').join(),
        date: DateTime.now().add(const Duration(hours: 2)), speechMode: 'on', speechVoice: '228'),
        onAck: () async {}, onSkip: () async {}, onPostpone: (at) async => at,
        onEdit: () => edited = true)))));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byKey(const ValueKey('detail-character-image')));
    await tester.runAsync(() => precacheImage(image.image, tester.element(find.byType(ReminderDetail))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('保存音频'));
    await tester.pumpAndSettle();
    expect(find.text('保存音频').hitTestable(), findsOneWidget);
    expect(find.text('编辑提醒').hitTestable(), findsOneWidget);
    await tester.tap(find.text('编辑提醒'));
    expect(edited, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
  });

}
