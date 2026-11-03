// AOT benchmark of the real app UI with deterministic native data. No ASR/TTS
// synthesis or microphone runs here: this deliberately isolates sheet rendering.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timed_memo/character_art.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/task_library.dart';

const revision = String.fromEnvironment('DETAIL_REVISION', defaultValue: 'local');
const longText = '早上七点半，城市刚刚醒来。地铁站里，人们一边看手机，一边快步走向闸机。'
  '今天的会议安排得有点紧，九点讨论方案，十点半汇报进度。';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile real detail entry and sustained scrolling', (tester) async {
    final frames = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
    binding.addTimingsCallback(collect);
    addTearDown(() => binding.removeTimingsCallback(collect));
    final rows = <Map<String, dynamic>>[];
    for (final archived in [false, true]) {
      for (final sid in [115, 228, 803]) {
        final r = Reminder(id: sid + 1, text: List.filled(8, longText).join(),
          date: DateTime(2030, 1, 1, 9), archived: archived,
          speechMode: 'on', speechVoice: '$sid', speechState: 'ready');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
          if (call.method == 'getState') {
            return jsonEncode({'reminders': [{...r.toJson(), 'speechState': 'ready'}],
              'defaults': {}, 'status': {'notifications': true, 'exact': true}});
          }
          if (call.method == 'initialReminderId') return 0;
          return null;
        });
        await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
        await tester.pumpWidget(const MemoApp()); await tester.pumpAndSettle();
        // Both revisions start with metadata ready; compare image decoding and
        // entry work rather than conflating it with the first-ever catalog read.
        await CharacterArtCatalog.load();
        if (archived) {
          await tester.tap(find.byTooltip('历史任务')); await tester.pumpAndSettle();
          expect(find.byType(TaskLibraryPage), findsOneWidget);
        }
        for (var visit = 0; visit < 3; visit++) {
          Future<void> measure(String phase, Future<void> Function() action) async {
            final start = developer.Timeline.now;
            await action();
            final end = developer.Timeline.now;
            // Profile batches arrive ~100ms apart. Flush without manufacturing
            // animation frames, then select only timestamps inside the action.
            await Future<void>.delayed(const Duration(milliseconds: 300));
            final sample = frames.where((f) {
              final at = f.timestampInMicroseconds(ui.FramePhase.buildStart);
              return at >= start && at <= end;
            }).toList();
            expect(sample, isNotEmpty, reason: '$phase must contain actual engine frames');
            final row = <String, dynamic>{'revision': revision, 'route': archived ? 'history' : 'home',
              'speaker': sid, 'visit': visit, 'phase': phase, 'elapsed_ms': (end - start) / 1000,
              'ui_us': sample.map((f) => f.buildDuration.inMicroseconds).toList(),
              'raster_us': sample.map((f) => f.rasterDuration.inMicroseconds).toList()};
            rows.add(row);
            // Android/Flutter log output can truncate individual long lines.
            // Send checked, numbered ASCII chunks, each comfortably below 1KB.
            final payload = base64Encode(utf8.encode(jsonEncode(row)));
            final total = (payload.length / 600).ceil();
            for (var part = 0; part < total; part++) {
              final end = (part + 1) * 600;
              debugPrint('DETAIL_CHUNK:${rows.length}:$part:$total:${payload.substring(part * 600, end < payload.length ? end : payload.length)}');
            }
          }
          await measure('open', () async {
            await tester.tap(find.text(r.text).first);
            await tester.pumpAndSettle(const Duration(milliseconds: 16));
          });
          expect(find.byType(ReminderDetail), findsOneWidget);
          final scroll = find.byKey(const ValueKey('reminder-detail-scroll'));
          // Settle any asynchronous decode before sustained scroll measurements.
          final images = find.byKey(const ValueKey('detail-character-image'));
          if (images.evaluate().isNotEmpty) {
            final image = tester.widget<Image>(images);
            await precacheImage(image.image, tester.element(images));
          }
          await tester.pumpAndSettle();
          await measure('outer-scroll', () async {
            final rect = tester.getRect(scroll);
            // In the right padding, outside the nested text viewport.
            await tester.timedDragFrom(Offset(rect.right - 6, rect.bottom - 40),
              const Offset(0, -240), const Duration(milliseconds: 800));
            await tester.pumpAndSettle(const Duration(milliseconds: 16));
            await tester.timedDragFrom(Offset(rect.right - 6, rect.top + 40),
              const Offset(0, 240), const Duration(milliseconds: 800));
            await tester.pumpAndSettle(const Duration(milliseconds: 16));
          });
          // Explicitly exercise the long正文 viewport as well as the outer list.
          final text = find.descendant(of: find.byType(ReminderDetail), matching: find.text(r.text));
          await tester.ensureVisible(text); await tester.pumpAndSettle();
          await measure('text-scroll', () async {
            final textScroll = find.ancestor(of: text, matching: find.byType(SingleChildScrollView)).first;
            final rect = tester.getRect(textScroll);
            await tester.timedDragFrom(rect.center, const Offset(0, -100), const Duration(milliseconds: 800));
            await tester.pumpAndSettle(const Duration(milliseconds: 16));
          });
          expect(find.text('编辑提醒').hitTestable(), findsOneWidget);
          Navigator.of(tester.element(find.byType(ReminderDetail))).pop();
          await tester.pumpAndSettle();
        }
      }
    }
    debugPrint('DETAIL_BENCHMARK_DONE:${jsonEncode({'revision': revision, 'measurements': rows.length, 'profile': kProfileMode})}');
    await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
