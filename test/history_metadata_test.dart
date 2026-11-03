import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/appearance.dart';
import 'package:timed_memo/design_tokens.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/widgets/widgets.dart';
import 'ui_preview_test.dart' show capture, previewKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['MEMO_UI_PREVIEWS'] != '1') return;
    final bytes = File(Platform.environment['MEMO_PREVIEW_FONT']!).readAsBytesSync();
    for (final family in ['Roboto', 'Ahem', 'FlutterTest']) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final accent in MemoAccent.values) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('history configuration badges follow ${accent.name}/${mode.name} at 320dp', (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(() { appearance.value = Appearance.defaults; });
        appearance.value = Appearance(mode: mode, accent: accent);
        final rows = [
          Reminder(id: 1, text: '每天语音任务', repeat: 'daily', speechMode: 'on'),
          Reminder(id: 2, text: '单次静音任务', speechMode: 'off'),
          Reminder(id: 3, text: '原来跟随默认', repeat: 'weekly', days: [1, 2, 3, 4, 5, 6, 7], speechMode: 'inherit'),
        ].map((r) => {...r.toJson(), 'completed': true, 'enabled': false,
          'archived': r.id == 3, 'lastAck': DateTime.now().millisecondsSinceEpoch,
          'speechState': 'off', 'resolvedSpeechEnabled': false}).toList();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
          if (call.method == 'getAppearance') return jsonEncode({'mode': mode.name, 'accent': accent.name});
          if (call.method == 'getState') return jsonEncode({'reminders': rows, 'defaults': {'speechMode': 'off'}, 'status': {}});
          return null;
        });
        await tester.pumpWidget(const RepaintBoundary(key: previewKey, child: MemoApp())); await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('历史任务')); await tester.pumpAndSettle();
        expect(find.text('每天'), findsOneWidget);
        expect(find.text('仅一次'), findsOneWidget);
        expect(find.text('语音开启'), findsOneWidget);
        expect(find.text('语音关闭'), findsOneWidget);
        expect(find.text('语音跟随默认'), findsOneWidget);
        expect(find.text('语音就绪'), findsNothing);
        expect(find.text('未启用'), findsNothing);
        final tags = find.byType(MemoTag);
        expect(tags, findsNWidgets(6));
        for (final element in tags.evaluate()) {
          final tag = element.widget as MemoTag;
          expect(tag.tone, MemoTagTone.brand);
          expect(tag.icon, isNotNull);
          final palette = MemoTokens.of(element).colors;
          expect(palette.brand700, MemoTokens.forAccent(accent,
            mode == ThemeMode.dark ? Brightness.dark : Brightness.light).colors.brand700);
          final icon = tester.widget<Icon>(find.descendant(of: find.byWidget(tag), matching: find.byType(Icon)));
          expect(icon.color, palette.brand700);
          final text = tester.widget<Text>(find.descendant(of: find.byWidget(tag), matching: find.byType(Text)));
          expect(text.style!.color, palette.brand700);
        }
        expect(tester.takeException(), isNull);
        if (Platform.environment['MEMO_UI_PREVIEWS'] == '1') {
          await capture(tester, 'history-${accent.name}-${mode.name}');
        }
        await tester.pumpWidget(const SizedBox()); await tester.pump();
      });
    }
  }
}
