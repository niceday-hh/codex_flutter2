import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/voice_catalog.dart';
import 'package:timed_memo/voice_group.dart';
import 'package:timed_memo/voice_groups_page.dart';
import 'package:timed_memo/reminder.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('custom membership intersects metadata and group references round-trip with a task', () async {
    final catalog = await VoiceCatalog.load();
    expect(catalog.candidates(language: 'ja', gender: 'female', members: {'104','303'}), ['303']);
    expect(catalog.candidates(language: 'ja', gender: 'male', members: {'104','303'}), isEmpty);
    final group = VoiceGroup(id: 'fav', name: '我的角色', voices: ['104','303']);
    expect(VoiceGroup.fromJson(group.toJson()).voices, group.voices);
    final r = Reminder(speechRandom: true, speechRandomGroup: 'fav', speechVoice: '303');
    expect(Reminder.fromJson(r.toJson()).speechRandomGroup, 'fav');
    final store = MemoStore()..defaults = {'speechRandom': true,'speechRandomGroup': 'fav'};
    expect(store.draft().speechRandomGroup, 'fav');
    expect(store.draft().speechVoice, isEmpty);
  });
  testWidgets('group editor saves the actual selected speaker IDs', (tester) async {
    VoiceGroup? saved;
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: TextButton(
      onPressed: () async { saved = await Navigator.push<VoiceGroup>(c, MaterialPageRoute(builder: (_) => const VoiceGroupEditor())); },
      child: const Text('编辑组'))))));
    await tester.tap(find.text('编辑组')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '睡前角色');
    await tester.enterText(find.byType(TextField).last, '303');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first); await tester.pump();
    await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(saved?.name, '睡前角色'); expect(saved?.voices, ['303']);
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
