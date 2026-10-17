import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/reminder.dart';
import 'package:timed_memo/voice_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('language and gender pools intersect and unknown roles do not leak into gender pools', () async {
    final catalog = await VoiceCatalog.load();
    expect(catalog.candidates().length, 804);
    expect(catalog.candidates(language: 'ja'), containsAll(['0', '148', '303']));
    expect(catalog.candidates(language: 'zh'), contains('228'));
    expect(catalog.candidates(gender: 'female'), contains('228'));
    expect(catalog.candidates(gender: 'male'), contains('104'));
    expect(catalog.candidates(gender: 'female'), isNot(contains('803')));
    final pool = catalog.candidates(language: 'ja', gender: 'male');
    final rng = Random(7);
    for (var i = 0; i < 40; i++) {
      expect(pool, contains(catalog.pick(language: 'ja', gender: 'male', random: rng)));
    }
    expect(catalog.pick(language: 'ja', gender: 'male', query: '没有这个角色'), isNull);
  });
  test('new drafts inherit random rules, old records stay fixed and selected voice roundtrips', () {
    final store = MemoStore()..defaults = {'speechRandom': true, 'speechRandomLanguage': 'ja', 'speechRandomGender': 'female'};
    final draft = store.draft();
    expect(draft.speechRandom, isTrue); expect(draft.speechRandomLanguage, 'ja');
    expect(draft.speechVoice, '');
    draft.speechVoice = '303';
    final copied = Reminder.fromJson(draft.toJson());
    expect(copied.speechVoice, '303'); expect(copied.speechRandomGender, 'female');
    expect(Reminder.fromJson(Reminder().toJson()..remove('speechRandom')).speechRandom, isFalse);
  });
}
