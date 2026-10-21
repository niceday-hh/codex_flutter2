import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/main.dart' show ReminderDetail;
import 'package:timed_memo/reminder_audio.dart';
import 'package:timed_memo/speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.wav';
  final job = {'lease': 'lease', 'key': key, 'text': '本条提醒正文', 'sid': 33, 'rate': .6};
  final reminder = Reminder(id: 7, text: '本条提醒正文', speechMode: 'off', speechState: 'off');
  Future<void> mount(WidgetTester tester, SpeechSession session) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      ReminderAudioPanel(reminder: reminder, session: session)))));
    await tester.pump();
  }
  testWidgets('cached reminder preview uses its saved ID, stops and completes without changing the task', (tester) async {
    final session = SpeechSession(); final calls = <String>[]; int? token; var released = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call.method);
      if (call.method == 'reminderAudioJob') { expect(call.arguments, 7); return jsonEncode({...job, 'ready': true}); }
      if (call.method == 'reminderAudioReady') return true;
      if (call.method == 'releaseReminderAudio') released++;
      if (call.method == 'playSpeechPreview') { final a = call.arguments as Map; expect(a['key'], key); token = a['token'] as int; return true; }
      return null;
    });
    await mount(tester, session);
    await tester.tap(find.text('试听提醒')); await tester.pumpAndSettle();
    expect(find.text('停止试听'), findsOneWidget); expect(released, 1);
    session.previewEnded(token!); await tester.pump(); expect(find.text('试听提醒'), findsOneWidget);
    expect(calls, isNot(contains('speechPreviewJob'))); expect(calls, isNot(contains('generateSpeech')));
    expect(calls, isNot(contains('save'))); expect(calls, isNot(contains('ack')));
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    session.status.dispose(); session.previewState.dispose();
  });
  testWidgets('download waits for generation and chooser completion, then reports success inline', (tester) async {
    final session = SpeechSession(); final generation = Completer<void>(), chooser = Completer<bool?>();
    var ready = false, exports = 0, released = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'reminderAudioJob') return jsonEncode({...job, 'ready': false});
      if (call.method == 'reminderAudioReady') return ready;
      if (call.method == 'generateSpeech') { expect(jsonDecode(call.arguments as String)['text'], '本条提醒正文'); await generation.future; ready = true; }
      if (call.method == 'exportReminderAudio') { exports++; expect(call.arguments, 'lease'); return chooser.future; }
      if (call.method == 'releaseReminderAudio') released++;
      return null;
    });
    await mount(tester, session); await tester.tap(find.text('保存音频')); await tester.pump();
    expect(find.textContaining('正在准备音频'), findsOneWidget); expect(exports, 0);
    generation.complete(); await tester.pump(); await tester.pump(); await tester.pump();
    expect(exports, 1); expect(released, 0);
    chooser.complete(true); await tester.pumpAndSettle();
    expect(find.text('音频已保存到所选位置。'), findsOneWidget); expect(released, 1);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    session.status.dispose(); session.previewState.dispose();
  });
  for (final action in ['试听提醒', '保存音频']) {
    testWidgets('closing the panel during generation prevents later $action side effects', (tester) async {
      final session = SpeechSession(); final generation = Completer<void>();
      var ready = false, sideEffects = 0, released = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'reminderAudioJob') return jsonEncode({...job, 'ready': false});
        if (call.method == 'reminderAudioReady') return ready;
        if (call.method == 'generateSpeech') { await generation.future; ready = true; }
        if (call.method == 'exportReminderAudio' || call.method == 'playSpeechPreview') sideEffects++;
        if (call.method == 'releaseReminderAudio') released++;
        return null;
      });
      await mount(tester, session); await tester.tap(find.text(action)); await tester.pump();
      await tester.pumpWidget(const SizedBox()); await tester.pump();
      generation.complete(); await tester.pumpAndSettle();
      expect(sideEffects, 0); expect(released, 1); expect(tester.takeException(), isNull);
      session.status.dispose(); session.previewState.dispose();
    });
  }
  for (final fails in [false, true]) {
    testWidgets('save ${fails ? 'failure' : 'cancellation'} stays visible in the open panel', (tester) async {
      final session = SpeechSession();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'reminderAudioJob') return jsonEncode({...job, 'ready': true});
        if (call.method == 'reminderAudioReady') return true;
        if (call.method == 'exportReminderAudio' && fails) throw PlatformException(code: 'EXPORT', message: '无法写入所选位置');
        return null;
      });
      await mount(tester, session); await tester.tap(find.text('保存音频')); await tester.pumpAndSettle();
      expect(find.text(fails ? '无法写入所选位置' : '已取消保存。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); await tester.pump();
      session.status.dispose(); session.previewState.dispose();
    });
  }
  testWidgets('candidate preparation requires explicit selection and keeps normal download disabled until decided', (tester) async {
    final session = SpeechSession(); var selections = 0, released = 0, previews = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'candidateReminderAudio') return jsonEncode({...job, 'ready': true, 'reminderId': 7});
      if (call.method == 'reminderAudioReady') return true;
      if (call.method == 'selectReminderAudio') { selections++; return true; }
      if (call.method == 'releaseReminderAudio') released++;
      if (call.method == 'playSpeechPreview') { previews++; return true; }
      return null;
    });
    await mount(tester, session); await tester.tap(find.text('换一版')); await tester.pumpAndSettle();
    expect(find.text('使用此版本'), findsOneWidget); expect(selections, 0); expect(released, 0);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('save-reminder-audio'))).onPressed, isNull);
    await tester.tap(find.text('试听新版本')); await tester.pumpAndSettle(); expect(previews, 1); expect(selections, 0);
    await tester.tap(find.text('停止试听')); await tester.pumpAndSettle();
    await tester.tap(find.text('使用此版本')); await tester.pumpAndSettle();
    expect(selections, 1); expect(released, 1); expect(find.textContaining('已使用此版本'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('save-reminder-audio'))).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump(); session.status.dispose(); session.previewState.dispose();
  });
  for (final close in [false, true]) {
    testWidgets('candidate ${close ? 'closed' : 'discarded'} releases its lease without selecting', (tester) async {
      final session = SpeechSession(); var selected = 0, released = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'candidateReminderAudio') return jsonEncode({...job, 'ready': true});
        if (call.method == 'reminderAudioReady') return true;
        if (call.method == 'selectReminderAudio') selected++;
        if (call.method == 'releaseReminderAudio') released++;
        return null;
      });
      await mount(tester, session); await tester.tap(find.text('换一版')); await tester.pumpAndSettle();
      if (close) { await tester.pumpWidget(const SizedBox()); } else { await tester.tap(find.text('放弃新版本')); }
      await tester.pumpAndSettle(); expect(selected, 0); expect(released, 1);
      await tester.pumpWidget(const SizedBox()); await tester.pump(); session.status.dispose(); session.previewState.dispose();
    });
  }
  testWidgets('closing during candidate generation never selects or starts later playback', (tester) async {
    final session = SpeechSession(); final generation = Completer<void>();
    var ready = false, released = 0, effects = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'candidateReminderAudio') return jsonEncode({...job, 'ready': false});
      if (call.method == 'reminderAudioReady') return ready;
      if (call.method == 'generateSpeech') { await generation.future; ready = true; }
      if (call.method == 'releaseReminderAudio') released++;
      if (call.method == 'selectReminderAudio' || call.method == 'playSpeechPreview') effects++;
      return null;
    });
    await mount(tester, session); await tester.tap(find.text('换一版')); await tester.pump();
    await tester.pumpWidget(const SizedBox()); generation.complete(); await tester.pumpAndSettle();
    expect(effects, 0); expect(released, 1); session.status.dispose(); session.previewState.dispose();
  });
  testWidgets('saving after a playback error replaces the old error with current inline feedback', (tester) async {
    final session = SpeechSession(); int? token;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'reminderAudioJob') return jsonEncode({...job, 'ready': true});
      if (call.method == 'reminderAudioReady' || call.method == 'exportReminderAudio') return true;
      if (call.method == 'playSpeechPreview') { token = (call.arguments as Map)['token'] as int; return true; }
      return null;
    });
    await mount(tester, session); await tester.tap(find.text('试听提醒')); await tester.pumpAndSettle();
    session.previewEnded(token!, error: '播放失败'); await tester.pump(); expect(find.text('播放失败'), findsOneWidget);
    await tester.tap(find.text('保存音频')); await tester.pumpAndSettle();
    expect(find.text('音频已保存到所选位置。'), findsOneWidget); expect(find.text('播放失败'), findsNothing);
    await tester.pumpWidget(const SizedBox()); await tester.pump(); session.status.dispose(); session.previewState.dispose();
  });
  testWidgets('long saved reminder remains scrollable on a small screen with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (_) async => null);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(size: Size(320, 568),
      textScaler: TextScaler.linear(1.6)), child: Scaffold(body: ReminderDetail(
        reminder: Reminder(id: 7, text: List.filled(20, '这是一条很长的提醒正文。').join()),
        onAck: () async {}, onEdit: () {})))));
    await tester.pump();
    await tester.ensureVisible(find.text('保存音频')); await tester.pumpAndSettle();
    expect(find.text('保存音频').hitTestable(), findsOneWidget); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
  test('an old completion or disposed owner cannot stop a newer preview', () async {
    final session = SpeechSession(); final a = Object(), b = Object(); final tokens = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'reminderAudioJob') return jsonEncode({...job, 'ready': true});
      if (call.method == 'reminderAudioReady') return true;
      if (call.method == 'playSpeechPreview') { tokens.add((call.arguments as Map)['token'] as int); return true; }
      return null;
    });
    await session.previewReminder(7, owner: a); await session.previewReminder(8, owner: b);
    session.previewEnded(tokens.first); session.stopPreview(owner: a);
    expect(session.previewState.value.playing, isTrue); expect(session.previewState.value.reminderId, 8);
    session.previewEnded(tokens.last); expect(session.previewState.value.playing, isFalse);
    session.stopPreview(); session.status.dispose(); session.previewState.dispose();
  });
}
