import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/appearance.dart';
import 'package:timed_memo/character_art.dart';
import 'package:timed_memo/design_tokens.dart';
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
  test('prepared palettes and subject framing stay valid for every bundled role', () {
    final raw = jsonDecode(File('assets/character_art/art_catalog.json').readAsStringSync()) as Map<String, dynamic>;
    final styles = jsonDecode(File('assets/character_art/art_styles.json').readAsStringSync()) as Map<String, dynamic>;
    final catalog = CharacterArtCatalog.fromJson(raw, styles: styles['images'] as Map<String, dynamic>);
    Color colour(String value) => Color(int.parse('ff${value.substring(1)}', radix: 16));
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }
    for (final art in catalog.entries.values) {
      expect(art.light, isNotNull, reason: art.asset); expect(art.dark, isNotNull, reason: art.asset);
      for (final roles in [art.light!, art.dark!]) {
        for (final pair in [['primary', 'onPrimary'], ['primaryContainer', 'onPrimaryContainer'],
            ['surface', 'onSurface'], ['surface', 'onSurfaceVariant']]) {
          expect(contrast(colour(roles[pair[0]]!), colour(roles[pair[1]]!)), greaterThanOrEqualTo(4.5), reason: art.asset);
        }
      }
      for (final size in [const Size(393, 740), const Size(320, 480), const Size(700, 280)]) {
        final rect = art.placement(size);
        expect(rect.width.isFinite && rect.width > 0 && rect.height.isFinite && rect.height > 0, isTrue);
        final focus = Offset(rect.left + art.focus.dx * rect.width / art.width, rect.top + art.focus.dy * rect.height / art.height);
        expect(focus.dx, closeTo(size.width * (art.isPortrait ? .73 : .79), .001)); expect(focus.dy, closeTo(art.isPortrait ? 126 : 96, .001));
      }
    }
    expect(catalog.entries['115']!.bounds.width, lessThan(640));
    expect(catalog.entries['228']!.light!['primary'], '#b62500');
    final fallback = CharacterArtCatalog.fromJson(raw, styles: {'assets/character_banners/genshin_keqing.webp': {'bounds': [0, 0, -1, 0], 'light': {'primary': 'bad'}}});
    expect(fallback.entries['115']!.light, isNull);
    expect(fallback.entries['115']!.bounds.width, 640);
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
          if (call.method == 'getState') {
            return jsonEncode({'reminders': [{...reminder.toJson(), 'speechState': 'ready'}],
              'defaults': {}, 'status': {'notifications': true, 'exact': true}});
          }
          if (call.method == 'initialReminderId') return 0;
          return null;
        });
        addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, null));
        final catalog = await tester.runAsync(() => CharacterArtCatalog.load());
        appearance.value = Appearance(mode: mode);
        await tester.pumpWidget(const RepaintBoundary(key: boundaryKey, child: MemoApp()));
        await tester.pumpAndSettle();
        await tester.tap(find.text(reminder.text).first);
        await tester.pumpAndSettle();
        // Asset futures run outside the fake clock used by widget tests.
        await tester.runAsync(() async { await Future<void>.delayed(Duration.zero); });
        await tester.pumpAndSettle();
        expect(find.byType(ReminderDetail), findsOneWidget);
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
        if (art != null) {
          final local = tester.element(find.byKey(const ValueKey('reminder-detail-scroll')));
          final roles = mode == ThemeMode.dark ? art.dark! : art.light!;
          expect(Theme.of(local).colorScheme.primary.toARGB32(), int.parse('ff${roles['primary']!.substring(1)}', radix: 16));
          expect(local.colors.brand500, Theme.of(local).colorScheme.primary);
          expect(Theme.of(tester.element(find.byType(MemoHome))).colorScheme.primary, isNot(Theme.of(local).colorScheme.primary));
          expect(find.text('到点语音播报当前关闭；试听和保存不会开启它。'), findsNothing);
        }
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
    await tester.runAsync(() async { await Future<void>.delayed(Duration.zero); });
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
