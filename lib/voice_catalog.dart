import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'speech_voices.dart';

const voiceLanguages = {'all': '不限配音来源', 'zh': '中文配音', 'ja': '日文配音'};
const voiceGenders = {'all': '不限角色性别', 'female': '女性角色', 'male': '男性角色'};

class VoiceCatalog {
  final List<Map<String, dynamic>> voices;
  VoiceCatalog(this.voices);
  static VoiceCatalog? _cached;
  static Future<VoiceCatalog>? _loading;
  static Future<VoiceCatalog> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load().then((catalog) { _cached = catalog; return catalog; })
      .whenComplete(() => _loading = null);
  }
  static Future<VoiceCatalog> _load() async {
    final raw = jsonDecode(await rootBundle.loadString('native/app/src/main/assets/voice_catalog.json')) as Map<String, dynamic>;
    final entries = (raw['voices'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (entries.length != speechVoiceNames.length) throw StateError('音色分组资料不完整');
    return VoiceCatalog(entries);
  }
  List<String> candidates({String language = 'all', String gender = 'all', String query = '', Set<String>? members}) {
    final key = query.toLowerCase();
    return [for (var i = 0; i < voices.length; i++)
      if ((members == null || members.contains('$i')) && (language == 'all' || voices[i]['language'] == language) &&
          (gender == 'all' || voices[i]['gender'] == gender) &&
          ('$i ${speechVoiceNames[i]}'.toLowerCase().contains(key))) '$i'];
  }
  String? pick({String language = 'all', String gender = 'all', String query = '', Random? random, Set<String>? members}) {
    final pool = candidates(language: language, gender: gender, query: query, members: members);
    return pool.isEmpty ? null : pool[(random ?? Random()).nextInt(pool.length)];
  }
  String tags(String id) {
    final v = voices[int.parse(id)];
    final gender = v['gender'] == 'unknown' ? '性别未标注' : voiceGenders[v['gender']];
    return '${voiceLanguages[v['language']]} · $gender';
  }
}
