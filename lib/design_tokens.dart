import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Design tokens for 超级提醒.
///
/// Everything visual should come from here. If a value is missing, add it to the
/// scale instead of hard-coding it at the call site — that is the whole point.
///
/// Contrast ratios in the comments are measured against white (`surface`) unless
/// another background is named, using the WCAG 2.x relative-luminance formula.
/// ---------------------------------------------------------------------------

/// Brand ramp, 50 → 900. One hue, ten steps, no ad-hoc purples.
abstract final class MemoColor {
  static const brand50 = Color(0xFFF7F4FF);
  static const brand100 = Color(0xFFF0ECFF); // lavender — tints, chips
  static const brand200 = Color(0xFFDDD2FF); // borders on tinted surfaces
  static const brand300 = Color(0xFFC0AAFB);
  static const brand400 = Color(0xFF8E6BF5);
  static const brand500 = Color(0xFF7252F6); // primary fill, icons on white (3.6:1)
  static const brand600 = Color(0xFF5B3FD9);
  static const brand700 = Color(0xFF5334CC); // text on brand100 (6.65:1)
  static const brand800 = Color(0xFF3E2699);
  static const brand900 = Color(0xFF2B1A6B); // gradient end / deepest ink

  /// Neutrals.
  static const ink = Color(0xFF25213A); // 15.6:1 — headings and body
  static const inkSoft = Color(0xFF4A4460); // 9.1:1 — secondary headings
  static const muted = Color(0xFF6B6484); // 5.5:1 on white, 5.1:1 on canvas
  static const line = Color(0xFFECE8F3); // hairline between cards; decorative
  static const lineStrong = Color(0xFFDDD8E8); // grips, drag handles
  static const outline = Color(0xFF8B8499); // 3.6:1 — borders of real inputs (WCAG 1.4.11)
  static const canvas = Color(0xFFF8F6FC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFFBFAFE);

  /// Semantic states — all ≥4.5:1 on their own tint.
  static const success = Color(0xFF1C7350);
  static const successSurface = Color(0xFFE7F5EF);
  static const warning = Color(0xFF8A4E0C);
  static const warningSurface = Color(0xFFFFF4E8);
  static const danger = Color(0xFFA8322A);
  static const dangerSurface = Color(0xFFFDEDEB);

  /// "Unread" accent. A 4×52 bar is a graphic, not text, so it only needs 3:1
  /// (WCAG 1.4.11) — the darker [warning] brown reads as a stain at this size
  /// and buries the one state that should jump out of the list. 3.4:1 on white.
  static const amber = Color(0xFFD2761E);
  static const amberSurface = Color(0xFFFFF3E4);
  static const amberInk = Color(0xFF7A4410); // 7.3:1 on amberSurface
  static const amberDeep = Color(0xFFB35F12); // 4.7:1 with white — the unread chip

  /// Translucent helpers (avoid scattering `withValues` magic numbers).
  static Color scrim([double alpha = .20]) => ink.withValues(alpha: alpha);
  static const onBrand = Color(0xEBFFFFFF); // 92% white on brand600
  static const onBrandSoft = Color(0xB8FFFFFF);

  /// The one place a gradient is allowed: the "next reminder" hero card.
  /// Three bands by hour of day, so the card reads as "morning" or "late
  /// night" without any extra chrome. All three hold white text at 5:1 or
  /// better, which is why nothing else had to change when they were added.
  static const heroTop = Color(0xFF6A4AF0);
  static const heroBottom = Color(0xFF4A2BC4);
  static const heroDawn = <Color>[Color(0xFF6E4BE6), Color(0xFFC2456F)];
  static const heroDay = <Color>[heroTop, heroBottom];
  static const heroNight = <Color>[Color(0xFF332F7A), Color(0xFF1A1F52)];

  /// 05:00–10:00 dawn, 10:00–17:00 day, the rest night.
  static List<Color> heroGradientFor(int hour) =>
    hour >= 5 && hour < 10 ? heroDawn : hour >= 10 && hour < 17 ? heroDay : heroNight;

  /// A single low-opacity brand wash behind the first screen. Painted once into
  /// its own layer, so it costs one fill — not one per scrolling frame.
  static const glowCore = Color(0x1C7252F6); // brand500 @ 11%
  static const glowEdge = Color(0x007252F6);

  /// Top-edge sheen inside the hero card, replacing the frosted panel that was
  /// dropped for frame-time reasons.
  static const heroSheen = Color(0x26FFFFFF); // 15% white
  static const heroSheenEnd = Color(0x00FFFFFF);
}

/// Eight steps, no free-form font sizes. Line heights are pre-baked so text
/// never relies on the default 1.2 that makes Chinese paragraphs look cramped.
abstract final class MemoText {
  static const display = TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -.4, color: MemoColor.ink);
  static const title = TextStyle(fontSize: 22, height: 1.28, fontWeight: FontWeight.w700, color: MemoColor.ink);
  static const headline = TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.w600, color: MemoColor.ink);
  static const subtitle = TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600, color: MemoColor.ink);
  static const body = TextStyle(fontSize: 14, height: 1.5, color: MemoColor.ink);
  static const label = TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w500, color: MemoColor.inkSoft);
  static const caption = TextStyle(fontSize: 12, height: 1.45, color: MemoColor.muted);
  static const overline = TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: .3, color: MemoColor.muted);

  /// Buttons: no baked-in colour, so `foregroundColor` from the theme wins.
  static const button = TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600);

  /// The two display numbers. Big enough that the time reads before the text,
  /// which is what makes a list of reminders scannable rather than readable.
  static const heroTime = TextStyle(fontSize: 40, height: 1.06, letterSpacing: -1.2,
    fontWeight: FontWeight.w800, color: Color(0xFFFFFFFF), fontFeatures: tabular);
  static const cardTime = TextStyle(fontSize: 26, height: 1.1, letterSpacing: -.8,
    fontWeight: FontWeight.w800, color: MemoColor.ink, fontFeatures: tabular);

  /// Card title: one step above [subtitle], so the clock and the text are not
  /// competing at almost the same size.
  static const cardTitle = TextStyle(fontSize: 16, height: 1.45, fontWeight: FontWeight.w600, color: MemoColor.ink);
  static const heroTitle = TextStyle(fontSize: 18, height: 1.4, fontWeight: FontWeight.w600, color: Color(0xFFFFFFFF));

  /// Numbers that must not jitter (countdowns, clocks, dates).
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];
}

/// Five radii. Anything outside this set is a bug, not a preference.
abstract final class MemoRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 22.0;
  static const xxl = 26.0;
  static const pill = 999.0;
}

/// 4pt spacing scale.
abstract final class MemoSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// Standard page inset. Every scroll view uses it so edges line up.
  static const page = EdgeInsets.symmetric(horizontal: 20);
}

/// Three elevations. Shadows are tinted ink, never pure black.
abstract final class MemoShadow {
  static const card = <BoxShadow>[BoxShadow(color: Color(0x060E0824), blurRadius: 14, offset: Offset(0, 5))];
  static const float = <BoxShadow>[BoxShadow(color: Color(0x120E0824), blurRadius: 22, offset: Offset(0, 10))];
  static const sheet = <BoxShadow>[BoxShadow(color: Color(0x240E0824), blurRadius: 40, offset: Offset(0, 18))];

  /// Brand-tinted lift under the hero card, so it reads as lit rather than cut out.
  static const hero = <BoxShadow>[BoxShadow(color: Color(0x3D4A2BC4), blurRadius: 26, offset: Offset(0, 12))];

  /// Pressed card: the shadow tightens as the card dips, so the finger gets a
  /// second, cheaper signal on top of the ripple.
  static const press = <BoxShadow>[BoxShadow(color: Color(0x0A0E0824), blurRadius: 5, offset: Offset(0, 1))];
}

/// Motion budget: everything is a one-shot response to input. Nothing loops.
///
/// The rule that keeps the frame budget intact: an animation may only run while
/// the user is touching the screen or while content is entering for the first
/// time. No `repeat()`, no idle pulse, no looping shimmer.
abstract final class MemoMotion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 200);
  static const curve = Curves.easeOutCubic;

  /// Finger-down scale on a tappable surface. Short enough to feel like
  /// pressure rather than a transition.
  static const press = Duration(milliseconds: 110);
  static const pressScale = 0.978;

  /// First-paint entrance. Every item resolves to "done" inside ~520ms.
  static const enter = Duration(milliseconds: 520);
  static const enterStep = 0.085; // stagger per item, in controller units
  static const enterSpan = 0.55; // how much of the timeline one item takes
  static const enterShift = 10.0; // px an item travels while fading in
  static const enterMaxItems = 6; // past this, items appear without delay
}

/// Theme extension so a future dark theme can swap the whole palette without
/// touching a single widget. Widgets read it through [MemoTokens.of].
@immutable
class MemoTokens extends ThemeExtension<MemoTokens> {
  final Color ink, inkSoft, muted, line, canvas, surface, brand, brandTint, brandInk;
  const MemoTokens({
    required this.ink, required this.inkSoft, required this.muted, required this.line,
    required this.canvas, required this.surface, required this.brand, required this.brandTint, required this.brandInk,
  });

  static const light = MemoTokens(
    ink: MemoColor.ink, inkSoft: MemoColor.inkSoft, muted: MemoColor.muted, line: MemoColor.line,
    canvas: MemoColor.canvas, surface: MemoColor.surface, brand: MemoColor.brand500,
    brandTint: MemoColor.brand100, brandInk: MemoColor.brand700,
  );

  static MemoTokens of(BuildContext context) =>
    Theme.of(context).extension<MemoTokens>() ?? light;

  @override MemoTokens copyWith({Color? ink, Color? inkSoft, Color? muted, Color? line,
    Color? canvas, Color? surface, Color? brand, Color? brandTint, Color? brandInk}) => MemoTokens(
      ink: ink ?? this.ink, inkSoft: inkSoft ?? this.inkSoft, muted: muted ?? this.muted,
      line: line ?? this.line, canvas: canvas ?? this.canvas, surface: surface ?? this.surface,
      brand: brand ?? this.brand, brandTint: brandTint ?? this.brandTint, brandInk: brandInk ?? this.brandInk);

  @override MemoTokens lerp(ThemeExtension<MemoTokens>? other, double t) {
    if (other is! MemoTokens) return this;
    return MemoTokens(
      ink: Color.lerp(ink, other.ink, t)!, inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      muted: Color.lerp(muted, other.muted, t)!, line: Color.lerp(line, other.line, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!, surface: Color.lerp(surface, other.surface, t)!,
      brand: Color.lerp(brand, other.brand, t)!, brandTint: Color.lerp(brandTint, other.brandTint, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!);
  }
}
