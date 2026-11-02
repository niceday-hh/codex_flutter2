import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/widgets/memo_time_sheet.dart';

void main() {
  final now = DateTime(2026, 11, 2, 20, 4);

  Future<void> open(WidgetTester tester, DateTime initial,
      {required ValueChanged<DateTime?> onResult, bool allowVoice = true}) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: Center(child: TextButton(
        onPressed: () async {
          onResult(await showMemoTimeSheet(context,
              initial: initial, allowVoice: allowVoice, now: () => now));
        },
        child: const Text('open'),
      )),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the current value and confirms it unchanged', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DateTime? result;
    await open(tester, DateTime(2026, 11, 2, 20, 4), onResult: (v) => result = v);
    expect(find.text('20:04'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 11, 2, 20, 4));
  });

  testWidgets('quick steps stack on the selected time', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester, DateTime(2026, 11, 2, 20, 4), onResult: (_) {});

    await tester.tap(find.text('+15 分钟'));
    await tester.pumpAndSettle();
    expect(find.text('20:19'), findsOneWidget);

    await tester.tap(find.text('+15 分钟'));
    await tester.pumpAndSettle();
    expect(find.text('20:34'), findsOneWidget);

    await tester.tap(find.text('明天此时'));
    await tester.pumpAndSettle();
    expect(find.text('明天'), findsOneWidget);
  });

  testWidgets('the hour shortcut never lands in the past', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester, DateTime(2026, 11, 2, 20, 4), onResult: (_) {});

    await tester.tap(find.text('整点'));
    await tester.pumpAndSettle();
    // 20:00 has already passed at 20:04, so the next round hour is 21:00.
    expect(find.text('21:00'), findsOneWidget);
  });

  testWidgets('the minute wheel moves one minute at a time', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester, DateTime(2026, 11, 2, 20, 4), onResult: (_) {});

    final minute = find.byType(ListWheelScrollView).last;
    await tester.drag(minute, const Offset(0, -46));
    await tester.pumpAndSettle();
    expect(find.text('20:05'), findsOneWidget);

    await tester.drag(minute, const Offset(0, -46));
    await tester.pumpAndSettle();
    expect(find.text('20:06'), findsOneWidget);
  });

  testWidgets('a past time cannot be confirmed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester, DateTime(2026, 11, 1, 9), onResult: (_) {});

    expect(find.text('这个时间已经过去'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('voice entry is hidden when the caller opts out', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester, DateTime(2026, 11, 2, 20, 4), onResult: (_) {}, allowVoice: false);
    expect(find.text('说时间'), findsNothing);
  });

  testWidgets('fits a 320dp screen with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await open(tester, DateTime(2026, 11, 2, 20, 4), onResult: (_) {});
    expect(tester.takeException(), isNull);
    expect(find.text('确定'), findsOneWidget);
  });
}
