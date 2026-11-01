import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/widgets/memo_countdown.dart';

/// The hero card promises "how long until the next one". These are the two
/// halves of that promise: the span is precise to the minute inside a day, and
/// the label flips from "after" to "ago" without a rebuild from above.
void main() {
  test('a span keeps minutes inside a day and drops them beyond it', () {
    expect(memoDistance(const Duration(seconds: 40)), '不到 1 分钟');
    expect(memoDistance(const Duration(minutes: 1)), '1 分钟');
    expect(memoDistance(const Duration(minutes: 59, seconds: 59)), '59 分钟');
    expect(memoDistance(const Duration(hours: 2, minutes: 15)), '2 小时 15 分钟');
    expect(memoDistance(const Duration(hours: 3)), '3 小时');
    expect(memoDistance(const Duration(days: 2, hours: 3, minutes: 40)), '2 天 3 小时');
    expect(memoDistance(const Duration(days: 1)), '1 天');
    expect(memoDistance(const Duration(days: -1, hours: -2)), '1 天 2 小时');
  });

  testWidgets('the pill counts forward, then says how long ago it rang', (tester) async {
    final future = DateTime.now().add(const Duration(hours: 1, minutes: 30, seconds: 20));
    await tester.pumpWidget(MaterialApp(home: Center(child: MemoCountdown(
      target: future, style: const TextStyle(fontSize: 12)))));
    expect(find.text('1 小时 30 分钟后'), findsOneWidget);

    final past = DateTime.now().subtract(const Duration(minutes: 12, seconds: 30));
    await tester.pumpWidget(MaterialApp(home: Center(child: MemoCountdown(
      target: past, style: const TextStyle(fontSize: 12), pastPrefix: '已提醒 '))));
    await tester.pump();
    expect(find.text('已提醒 12 分钟'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
