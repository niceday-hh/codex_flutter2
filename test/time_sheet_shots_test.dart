// Screenshot harness for the time sheet, not a regression test. Run with:
//
//   MEMO_UI_PREVIEWS=1 \
//   MEMO_PREVIEW_FONT=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
//   flutter test test/time_sheet_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/design_tokens.dart';
import 'package:timed_memo/widgets/memo_time_sheet.dart';

const previewKey = ValueKey('time-preview');
final previewsEnabled = Platform.environment['MEMO_UI_PREVIEWS'] == '1';

void main() {
  setUpAll(() async {
    if (!previewsEnabled) return;
    final sans = File(Platform.environment['MEMO_PREVIEW_FONT']!).readAsBytesSync();
    for (final family in ['Roboto', 'Ahem', 'FlutterTest']) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(sans)))).load();
    }
    final serif = File('assets/fonts/MemoSerif-Regular.otf').readAsBytesSync();
    await (FontLoader('MemoSerif')..addFont(Future.value(ByteData.sublistView(serif)))).load();
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final dark in [false, true]) {
    testWidgets('shoot the ${dark ? 'dark' : 'light'} sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tokens = dark ? MemoTokens.dark : MemoTokens.light;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          // The token styles carry no family; without this the test engine
          // falls back to Ahem and every glyph in the shot is a box.
          fontFamily: 'Roboto',
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [tokens],
          colorScheme: ColorScheme.fromSeed(
            seedColor: tokens.colors.brand500,
            brightness: dark ? Brightness.dark : Brightness.light),
        ),
        builder: (context, child) => DefaultTextStyle(
          style: const TextStyle(fontFamily: 'Roboto', fontSize: 14),
          child: child!),
        home: RepaintBoundary(key: previewKey, child: Container(
          color: tokens.colors.canvas,
          alignment: Alignment.bottomCenter,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(393, 852)),
            child: MemoTimeSheet(
              initial: DateTime(2026, 11, 2, 19, 15),
              now: () => DateTime(2026, 11, 2, 18, 42),
            ),
          ),
        )),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(previewKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('ui-shots/时间弹层-${dark ? '深色' : '浅色'}.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }, skip: !previewsEnabled);
  }
}
