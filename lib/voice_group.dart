class VoiceGroup {
  final String id, name;
  final List<String> voices;
  const VoiceGroup({required this.id, required this.name, required this.voices});
  factory VoiceGroup.fromJson(Map<String, dynamic> json) => VoiceGroup(
    id: json['id'] as String, name: json['name'] as String,
    voices: (json['voices'] as List).cast<String>());
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'voices': voices};
}
