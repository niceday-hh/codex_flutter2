import 'dart:convert';

import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'reminder.dart' show native;

/// What the user picked under 设置 → 外观与主题: a brightness mode and one of
/// the four brand ramps. Everything else — spacing, radii, type — stays on the
/// design tokens, because a settings screen with thirty switches is not
/// customisation, it is homework.
@immutable
class Appearance {
  final ThemeMode mode;
  final MemoAccent accent;

  const Appearance({this.mode = ThemeMode.system, this.accent = MemoAccent.violet});

  static const defaults = Appearance();

  Appearance copyWith({ThemeMode? mode, MemoAccent? accent}) =>
    Appearance(mode: mode ?? this.mode, accent: accent ?? this.accent);

  /// `system` / `light` / `dark` — the same words the native side stores, so a
  /// value written by an older build still parses.
  static ThemeMode modeOf(String? id) => switch (id) {
    'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system,
  };

  static MemoAccent accentOf(String? id) =>
    MemoAccent.values.firstWhere((a) => a.name == id, orElse: () => MemoAccent.violet);

  Map<String, String> toJson() => {'mode': mode.name, 'accent': accent.name};

  @override bool operator ==(Object other) =>
    other is Appearance && other.mode == mode && other.accent == accent;

  @override int get hashCode => Object.hash(mode, accent);
}

/// Holds the current appearance and persists changes through the native
/// channel. A `ValueNotifier` rather than a store field: the theme sits above
/// the reminder data, and rebuilding `MaterialApp` is all a change requires.
class AppearanceController extends ValueNotifier<Appearance> {
  AppearanceController([super.value = Appearance.defaults]);

  bool loaded = false;

  Future<void> load() async {
    try {
      final raw = await native.invokeMethod<String>('getAppearance');
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        value = Appearance(mode: Appearance.modeOf(json['mode'] as String?),
          accent: Appearance.accentOf(json['accent'] as String?));
      }
    } catch (_) {
      // A missing native side (tests, a downgrade) simply keeps the defaults.
    } finally {
      loaded = true;
    }
  }

  Future<void> setMode(ThemeMode mode) => _apply(value.copyWith(mode: mode));

  Future<void> setAccent(MemoAccent accent) => _apply(value.copyWith(accent: accent));

  Future<void> _apply(Appearance next) async {
    if (next == value) return;
    value = next;
    try {
      await native.invokeMethod('saveAppearance', jsonEncode(next.toJson()));
    } catch (_) {
      // The UI already switched; failing to persist must not revert it mid-tap.
    }
  }
}

/// One instance for the app. Tests construct their own controller when they
/// need to, and read the default otherwise.
final appearance = AppearanceController();
