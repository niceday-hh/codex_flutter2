import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/character_art.dart';
import 'package:timed_memo/design_tokens.dart';
import 'package:timed_memo/main.dart';
import 'package:timed_memo/reminder.dart';

const size = Size(360, 700);

Future<CharacterBackdropBake> _bakeFor(WidgetTester tester, String speaker, {Brightness brightness = Brightness.light}) async {
  final catalog = (await tester.runAsync(() => CharacterArtCatalog.load()))!;
  final art = catalog.entries[speaker]!;
  final palette = (brightness == Brightness.dark ? MemoPalette.dark : MemoPalette.light)
    .withArtRoles((brightness == Brightness.dark ? art.dark : art.light)!);
  return (await tester.runAsync(() => bakeCharacterBackdrop(art, size, palette, 2)))!;
}

void main() {
  testWidgets('bake renders both layers at the requested density', (tester) async {
    final bake = await _bakeFor(tester, '228');
    expect(bake.underlay.width, 720);
    expect(bake.underlay.height, 1400);
    expect(bake.overlay.width, 720);
    expect(bake.overlay.height, 1400);
    expect(bake.bytes, 720 * 1400 * 4 * 2);
    bake.underlay.dispose();
    bake.overlay.dispose();
  });

  testWidgets('cache keeps a bounded working set and survives repeats', (tester) async {
    final cache = CharacterBackdropCache.instance;
    cache.clear();
    final bake = await _bakeFor(tester, '228');
    for (var i = 0; i < 8; i++) {
      final value = await tester.runAsync(() => cache.obtain('k$i', () async => bake));
      expect(value, isNotNull);
    }
    expect(cache.length, lessThanOrEqualTo(CharacterBackdropCache.maxEntries));
    // A second open of a retained entry must not rebuild it.
    var built = 0;
    final retained = cache.peek('k7');
    expect(retained, isNotNull);
    final again = await tester.runAsync(() => cache.obtain('k7', () async { built++; return bake; }));
    expect(again, same(retained));
    expect(built, 0);
    cache.clear();
  });

  testWidgets('prewarm fills the cache before the first open', (tester) async {
    final cache = CharacterBackdropCache.instance;
    cache.clear();
    final catalog = (await tester.runAsync(() => CharacterArtCatalog.load()))!;
    final art = catalog.entries['228']!;
    final palette = MemoPalette.light.withArtRoles(art.light!);
    const target = Size(393, 714);
    // The prewarm pass waits for the home entrance to settle, then bakes; the
    // delay has to live in the real zone to fire.
    await tester.runAsync(() async {
      cache.prewarm(speakers: const ['228'], size: target, palette: palette, brightness: Brightness.light);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    expect(cache.length, 1);
    expect(cache.peek(CharacterBackdropCache.keyFor('228', target, Brightness.light, palette)), isNotNull);
    cache.clear();
  });

  testWidgets('a prewarmed sheet starts on textures', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 760 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final cache = CharacterBackdropCache.instance;
    cache.clear();
    final catalog = (await tester.runAsync(() => CharacterArtCatalog.load()))!;
    final art = catalog.entries['228']!;
    final palette = MemoPalette.light.withArtRoles(art.light!);
    const target = Size(393, 714);
    await tester.runAsync(() async {
      cache.prewarm(speakers: const ['228'], size: target, palette: palette, brightness: Brightness.light);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    expect(cache.length, 1);

    final reminder = Reminder(id: 12, text: '背景烘焙', date: DateTime(2030, 1, 1, 9),
      speechMode: 'on', speechVoice: '228', speechState: 'ready');
    final host = MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReminderDetail(reminder: reminder, onAck: () async {},
          onSkip: () async {}, onPostpone: (at) async => at, onEdit: () {})),
      child: const Text('打开')))));
    await tester.pumpWidget(host);
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    // Hit means the first painted frame already uses the textures, not painters.
    expect(find.byType(RawImage), findsWidgets);
    Navigator.of(tester.element(find.byType(ReminderDetail))).pop();
    await tester.pumpAndSettle();
    cache.clear();
  });

  testWidgets('detail sheet swaps the painters for baked layers', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 760 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    CharacterBackdropCache.instance.clear();
    final reminder = Reminder(id: 12, text: '背景烘焙', date: DateTime(2030, 1, 1, 9),
      speechMode: 'on', speechVoice: '228', speechState: 'ready');
    final host = MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReminderDetail(reminder: reminder, onAck: () async {},
          onSkip: () async {}, onPostpone: (at) async => at, onEdit: () {})),
      child: const Text('打开')))));
    await tester.pumpWidget(host);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsWidgets);
    // Let the offscreen render finish, then the sheet rebuilds on textures.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    expect(CharacterBackdropCache.instance.length, 1);
    expect(find.byType(RawImage), findsWidgets);
    Navigator.of(tester.element(find.byType(ReminderDetail))).pop();
    await tester.pumpAndSettle();
    CharacterBackdropCache.instance.clear();
  });
}
