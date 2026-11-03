import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

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
  final Rect bounds;
  final Offset focus;
  final Map<String, String>? light, dark;
  const CharacterArt({required this.asset, required this.layout, required this.width, required this.height,
    required this.bounds, required this.focus, this.light, this.dark});
  bool get isPortrait => layout == 'portrait_contain';

  /// Position the subject rather than its transparent source canvas. The face
  /// landmark stays at the top right while unimportant body/weapon edges crop.
  Rect placement(Size size) {
    final portrait = isPortrait;
    final wantedHeight = portrait ? math.min(640.0, math.max(500.0, size.height * .82)) : 310.0;
    final scale = layout == 'wide_contain' ? size.width / bounds.width
      : math.max(size.width * .78 / bounds.width, wantedHeight / bounds.height);
    final x = size.width * (portrait ? .73 : .79) - focus.dx * scale;
    final y = (portrait ? 126 : 96) - focus.dy * scale;
    return Rect.fromLTWH(x, y, width * scale, height * scale);
  }
}

class CharacterArtCatalog {
  final Map<String, CharacterArt> entries;
  CharacterArtCatalog(this.entries);
  static Future<CharacterArtCatalog>? _loading;
  static CharacterArtCatalog? _cached;
  static Future<CharacterArtCatalog> load() => _loading ??= Future.wait([
      rootBundle.loadString('assets/character_art/art_catalog.json'),
      rootBundle.loadString('assets/character_art/art_styles.json').catchError((Object _) => '{}'),
    ]).then((raw) {
      final styles = jsonDecode(raw[1]) as Map<String, dynamic>;
      return _cached = CharacterArtCatalog.fromJson(jsonDecode(raw[0]) as Map<String, dynamic>,
        styles: styles['images'] as Map<String, dynamic>? ?? {});
    }).catchError((Object _) => CharacterArtCatalog({}));

  factory CharacterArtCatalog.fromJson(Map<String, dynamic> data, {Map<String, dynamic> styles = const {}}) {
    final entries = <String, CharacterArt>{};
    Map<String, String>? palette(dynamic value) {
      const required = ['surface', 'background', 'onSurface', 'onSurfaceVariant', 'primary',
        'onPrimary', 'primaryContainer', 'onPrimaryContainer', 'outline', 'outlineVariant'];
      if (value is! Map || required.any((key) => value[key] is! String ||
          !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value[key] as String))) { return null; }
      return {for (final key in required) key: value[key] as String};
    }
    for (final entry in data.entries) {
      final id = int.tryParse(entry.key), row = entry.value;
      if (id == null || id < 0 || id >= 804 || row is! Map) continue;
      final asset = row['asset'], layout = row['layout'], w = row['width'], h = row['height'];
      if (asset is! String || !RegExp(r'^assets/character_(?:banners|portraits)/[a-z0-9_-]+\.webp$').hasMatch(asset) ||
          !const ['banner', 'portrait_contain', 'wide_contain'].contains(layout) ||
          w is! int || h is! int || w <= 0 || h <= 0 || w > 768 || h > 768) { continue; }
      var bounds = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
      final style = styles[asset] is Map ? styles[asset] as Map : const {};
      final b = style['bounds'], f = style['focus'];
      if (b is List && b.length == 4 && b.every((v) => v is num && v.isFinite)) {
        final rect = Rect.fromLTRB((b[0] as num).toDouble(), (b[1] as num).toDouble(),
          (b[2] as num).toDouble(), (b[3] as num).toDouble());
        if (rect.width > 0 && rect.height > 0 && rect.left >= 0 && rect.top >= 0 && rect.right <= w && rect.bottom <= h) { bounds = rect; }
      }
      var focus = Offset(bounds.center.dx, bounds.top + bounds.height * .25);
      if (f is List && f.length == 2 && f.every((v) => v is num && v.isFinite)) {
        final candidate = Offset((f[0] as num).toDouble(), (f[1] as num).toDouble());
        if (bounds.contains(candidate)) { focus = candidate; }
      }
      entries['$id'] = CharacterArt(asset: asset, layout: layout as String, width: w, height: h,
        bounds: bounds, focus: focus, light: palette(style['light']), dark: palette(style['dark']));
    }
    return CharacterArtCatalog(entries);
  }
}

/// A local Theme updates both Material buttons and the app's semantic tokens.
/// It never mutates the global AppearanceController or the editor's theme.
ThemeData characterDetailTheme(ThemeData parent, Map<String, String> roles) {
  final palette = (parent.extension<MemoTokens>() ?? MemoTokens.light).colors.withArtRoles(roles);
  final scheme = parent.colorScheme.copyWith(primary: palette.brand500, onPrimary: palette.onBrand,
    primaryContainer: palette.brand200, onPrimaryContainer: palette.brand800,
    secondary: palette.brand500, onSecondary: palette.onBrand,
    secondaryContainer: palette.brand200, onSecondaryContainer: palette.brand800,
    tertiary: palette.brand500, onTertiary: palette.onBrand, surfaceTint: palette.brand500,
    surface: palette.surface, onSurface: palette.ink, outline: palette.outline, outlineVariant: palette.line);
  return parent.copyWith(colorScheme: scheme,
    extensions: [...parent.extensions.values.where((value) => value is! MemoTokens),
      MemoTokens(colors: palette, text: MemoType(palette))],
    textTheme: parent.textTheme.apply(bodyColor: palette.ink, displayColor: palette.ink),
    filledButtonTheme: FilledButtonThemeData(style: parent.filledButtonTheme.style?.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled)
        ? palette.ink.withValues(alpha: .12) : palette.brand500),
      foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled)
        ? palette.muted : palette.onBrand))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: palette.brand700,
      textStyle: parent.textTheme.labelLarge)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: parent.outlinedButtonTheme.style?.copyWith(
      foregroundColor: WidgetStatePropertyAll(palette.brand700), side: WidgetStatePropertyAll(BorderSide(color: palette.line)))));
}

/// All art and colour metadata is local. No image analysis or blur on navigation.
class CharacterDetailBackdrop extends StatelessWidget {
  final String? speaker;
  final Widget Function(BuildContext, CharacterArt?) builder;
  const CharacterDetailBackdrop({super.key, required this.speaker, required this.builder});

  @override Widget build(BuildContext context) {
    if (speaker == null) return ColoredBox(color: context.colors.surfaceAlt, child: builder(context, null));
    return FutureBuilder<CharacterArtCatalog>(future: CharacterArtCatalog.load(), initialData: CharacterArtCatalog._cached,
      builder: (context, snapshot) {
        final art = snapshot.data?.entries[speaker];
        if (art == null) return ColoredBox(color: context.colors.surfaceAlt, child: builder(context, null));
        final roles = Theme.of(context).brightness == Brightness.dark ? art.dark : art.light;
        return Theme(data: roles == null ? Theme.of(context) : characterDetailTheme(Theme.of(context), roles),
          child: Builder(builder: (context) => ColoredBox(color: context.colors.surfaceAlt,
            child: ClipRect(child: Stack(children: [
              Positioned.fill(child: IgnorePointer(child: ExcludeSemantics(child: RepaintBoundary(
                child: LayoutBuilder(builder: (context, box) {
                  final base = context.colors.surfaceAlt, tint = context.colors.brand500;
                  final rect = art.placement(box.biggest);
                  final bottom = rect.top + art.bounds.bottom * rect.height / art.height;
                  final fadeEnd = bottom.clamp(math.min(240.0, box.maxHeight), box.maxHeight).toDouble();
                  final fadeStart = math.max(0.0, fadeEnd - (art.isPortrait ? 220 : 110));
                  return Stack(children: [
                    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                      gradient: RadialGradient(center: const Alignment(.9, -.7), radius: 1.15,
                        colors: [tint.withValues(alpha: .13), tint.withValues(alpha: 0)])))),
                    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                      gradient: RadialGradient(center: const Alignment(-.7, .6), radius: 1.2,
                        colors: [context.colors.brand200.withValues(alpha: .30), base.withValues(alpha: 0)])))),
                    Positioned.fromRect(rect: rect, child: _DecodedCharacterArt(art: art)),
                    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                      gradient: LinearGradient(stops: const [0, .40, .54, .68, 1], colors: [
                        base, base.withValues(alpha: .99), base.withValues(alpha: .94),
                        base.withValues(alpha: .18), base.withValues(alpha: .03)])))),
                    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        stops: [0, fadeStart / box.maxHeight, fadeEnd / box.maxHeight, 1],
                        colors: [base.withValues(alpha: 0), base.withValues(alpha: .04), base, base])))),
                  ]);
                }))))),
              builder(context, art),
            ])))));
      });
  }
}

/// Keep a small working set across sheet visits instead of decoding on every
/// open. This does not change Flutter's global cache limits or pin live images.
class CharacterImageCache with WidgetsBindingObserver {
  CharacterImageCache._();
  static final instance = CharacterImageCache._();
  static const maxEntries = 6, maxBytes = 6 * 1024 * 1024;
  final _recent = <String, CharacterArt>{}; // insertion order is the LRU order
  bool _observing = false;
  int get estimatedBytes => _recent.values.fold(0, (sum, art) => sum + art.width * art.height * 4);
  int get length => _recent.length;
  ImageProvider provider(CharacterArt art) => ResizeImage.resizeIfNeeded(
    art.width, art.height, AssetImage(art.asset));
  void touch(CharacterArt art) {
    if (!_observing) { WidgetsBinding.instance.addObserver(this); _observing = true; }
    _recent.remove(art.asset);
    _recent[art.asset] = art;
    while (_recent.length > maxEntries || estimatedBytes > maxBytes) {
      _evict(_recent.remove(_recent.keys.first)!);
    }
  }
  void _evict(CharacterArt art) { unawaited(provider(art).evict().catchError((Object _) => false)); }
  void clear() {
    final old = _recent.values.toList(); _recent.clear();
    for (final art in old) { _evict(art); }
  }
  @override void didHaveMemoryPressure() => clear();
}

class _DecodedCharacterArt extends StatefulWidget {
  final CharacterArt art;
  const _DecodedCharacterArt({required this.art});
  @override State<_DecodedCharacterArt> createState() => _DecodedCharacterArtState();
}
class _DecodedCharacterArtState extends State<_DecodedCharacterArt> {
  @override void initState() { super.initState(); CharacterImageCache.instance.touch(widget.art); }
  @override void didUpdateWidget(_DecodedCharacterArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.art.asset != widget.art.asset) CharacterImageCache.instance.touch(widget.art);
  }
  @override Widget build(BuildContext context) => Image(
    image: CharacterImageCache.instance.provider(widget.art), key: const ValueKey('detail-character-image'),
    width: double.infinity, height: double.infinity, fit: BoxFit.contain,
    alignment: Alignment.topRight, filterQuality: FilterQuality.low,
    errorBuilder: (_, __, ___) => const SizedBox.shrink());
}
