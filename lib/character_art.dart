import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';
import 'reminder.dart';

/// Resolved by the same native settings used for the selected reminder audio.
/// The fallback keeps older channel fixtures compatible; it never samples a voice.
String? reminderArtSpeaker(Reminder reminder, Map<String, dynamic> defaults) {
  final enabled = reminder.resolvedSpeechEnabled ??
    (reminder.speechMode == 'on' || reminder.speechMode == 'inherit' && defaults['speechMode'] == 'on');
  if (!enabled) return null;
  final voice = reminder.resolvedSpeechVoice ?? (reminder.speechVoice.isNotEmpty
    ? reminder.speechVoice : defaults['speechVoice'] as String? ?? '228');
  final id = int.tryParse(voice);
  return id != null && id >= 0 && id < 804 ? '$id' : null;
}

@immutable
class CharacterArt {
  final String asset, layout;
  final int width, height;
  const CharacterArt({required this.asset, required this.layout, required this.width, required this.height});
  bool get isPortrait => layout == 'portrait_contain';
}

class CharacterArtCatalog {
  final Map<String, CharacterArt> entries;
  CharacterArtCatalog(this.entries);
  static Future<CharacterArtCatalog>? _loading;
  static Future<CharacterArtCatalog> load() => _loading ??= rootBundle
    .loadString('assets/character_art/art_catalog.json')
    .then((raw) => CharacterArtCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>))
    .catchError((Object _) => CharacterArtCatalog({}));

  factory CharacterArtCatalog.fromJson(Map<String, dynamic> data) {
    final entries = <String, CharacterArt>{};
    for (final entry in data.entries) {
      final id = int.tryParse(entry.key), row = entry.value;
      if (id == null || id < 0 || id >= 804 || row is! Map) continue;
      final asset = row['asset'], layout = row['layout'], w = row['width'], h = row['height'];
      if (asset is! String || !RegExp(r'^assets/character_(?:banners|portraits)/[a-z0-9_-]+\.webp$').hasMatch(asset) ||
          !const ['banner', 'portrait_contain', 'wide_contain'].contains(layout) ||
          w is! int || h is! int || w <= 0 || h <= 0 || w > 768 || h > 768) { continue; }
      entries['$id'] = CharacterArt(asset: asset, layout: layout as String, width: w, height: h);
    }
    return CharacterArtCatalog(entries);
  }
}

/// Local, decorative artwork. Navigation never waits on the catalogue or codec.
/// Only the current image is decoded; callers do not prefetch the collection.
class CharacterDetailBackdrop extends StatelessWidget {
  final String? speaker;
  final Widget Function(BuildContext, CharacterArt?) builder;
  const CharacterDetailBackdrop({super.key, required this.speaker, required this.builder});

  @override Widget build(BuildContext context) {
    if (speaker == null) return builder(context, null);
    return FutureBuilder<CharacterArtCatalog>(future: CharacterArtCatalog.load(), builder: (context, snapshot) {
      final art = snapshot.data?.entries[speaker];
      return ClipRect(child: Stack(children: [
        if (art != null) Positioned.fill(child: IgnorePointer(child: ExcludeSemantics(
          child: RepaintBoundary(child: LayoutBuilder(builder: (context, box) {
            final base = context.colors.surfaceAlt;
            return Stack(children: [
              Positioned(top: 0, right: art.isPortrait ? -box.maxWidth * .18 : 0,
                left: box.maxWidth * (art.isPortrait ? .28 : .12),
                height: art.isPortrait ? box.maxHeight : 230,
                child: _DecodedCharacterArt(art: art)),
              // The text column ends at 60%; keep that zone almost opaque in
              // BOTH themes. The exposed face on the right keeps its colours.
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(stops: const [0, .48, .60, .70, 1], colors: [
                  base, base.withValues(alpha: .99), base.withValues(alpha: .96),
                  base.withValues(alpha: .14), base.withValues(alpha: .04)])))),
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  stops: const [0, .30, .72, 1], colors: [base.withValues(alpha: 0),
                    base.withValues(alpha: .05), base.withValues(alpha: .62), base])))),
            ]);
          })),
        ))),
        builder(context, art),
      ]));
    });
  }
}

/// Evict this decoration on exit instead of retaining every role visited in the
/// global image cache. No other page currently displays these asset providers.
class _DecodedCharacterArt extends StatefulWidget {
  final CharacterArt art;
  const _DecodedCharacterArt({required this.art});
  @override State<_DecodedCharacterArt> createState() => _DecodedCharacterArtState();
}
class _DecodedCharacterArtState extends State<_DecodedCharacterArt> {
  ImageProvider _provider(CharacterArt art) => ResizeImage.resizeIfNeeded(
    art.width, art.height, AssetImage(art.asset));
  void _release(CharacterArt art) {
    unawaited(_provider(art).evict().catchError((Object _) => false));
  }
  @override void didUpdateWidget(_DecodedCharacterArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.art.asset != widget.art.asset) _release(oldWidget.art);
  }
  @override void dispose() { _release(widget.art); super.dispose(); }
  @override Widget build(BuildContext context) => Image(
    image: _provider(widget.art), key: const ValueKey('detail-character-image'),
    width: double.infinity, height: double.infinity, fit: BoxFit.contain,
    alignment: Alignment.topRight, filterQuality: FilterQuality.low,
    errorBuilder: (_, __, ___) => const SizedBox.shrink());
}
