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
  /// The dark canvas. Also the label colour for pastel fills in dark mode,
  /// where white would only reach 3.5:1.
  static const night = Color(0xFF0E0D13);
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

/// Four complete brand ramps. Violet is the shipped identity; the other three
/// are alternatives picked in 设置 → 外观与主题. A ramp carries its own hero
/// gradient stops, so the "next reminder" card never ends up blue on a violet
/// page.
///
/// The values are deliberately the darker end of each hue: `c500` fills a
/// button that carries white text, and every ramp is asserted in
/// `test/ui_system_test.dart` (500 on white ≥4.5:1, 700 on white ≥7:1, and in
/// dark mode 500 on the page ≥4.5:1).
enum MemoAccent {
  violet('紫'), indigo('靛蓝'), teal('青碧'), ember('赭橙');

  const MemoAccent(this.label);
  final String label;
}

@immutable
class MemoBrand {
  final Color c50, c100, c200, c400, c500, c600, c700, c800;

  /// Second stop of the morning gradient: a warm turn, so dawn does not read
  /// as midday.
  final Color dawn;
  final Color nightTop, nightBottom;

  const MemoBrand({
    required this.c50, required this.c100, required this.c200, required this.c400,
    required this.c500, required this.c600, required this.c700, required this.c800,
    required this.dawn, required this.nightTop, required this.nightBottom,
  });

  List<Color> get gradientDay => [c600, c800];
  List<Color> get gradientDawn => [c600, dawn];
  List<Color> get gradientNight => [nightTop, nightBottom];
}

const brandVioletLight = MemoBrand(
  c50: Color(0xFFF7F4FF), c100: Color(0xFFF0ECFF), c200: Color(0xFFDDD2FF), c400: Color(0xFF8E6BF5),
  c500: Color(0xFF7252F6), c600: Color(0xFF5B3FD9), c700: Color(0xFF5334CC), c800: Color(0xFF3E2699),
  dawn: Color(0xFFC2456F), nightTop: Color(0xFF332F7A), nightBottom: Color(0xFF1A1F52));

const brandIndigoLight = MemoBrand(
  c50: Color(0xFFF1F4FF), c100: Color(0xFFE5EAFF), c200: Color(0xFFC9D4FE), c400: Color(0xFF6B87F5),
  c500: Color(0xFF4468E8), c600: Color(0xFF3253CC), c700: Color(0xFF2A45A8), c800: Color(0xFF1D3178),
  dawn: Color(0xFFB84A87), nightTop: Color(0xFF26305E), nightBottom: Color(0xFF161C3C));

const brandTealLight = MemoBrand(
  c50: Color(0xFFEDFAF6), c100: Color(0xFFDCF5EE), c200: Color(0xFFB7E7DA), c400: Color(0xFF3FA890),
  c500: Color(0xFF1A8168), c600: Color(0xFF146D59), c700: Color(0xFF105B4A), c800: Color(0xFF0A4033),
  dawn: Color(0xFFC2603F), nightTop: Color(0xFF1B3A36), nightBottom: Color(0xFF0F2220));

const brandEmberLight = MemoBrand(
  c50: Color(0xFFFFF7EF), c100: Color(0xFFFFEEDD), c200: Color(0xFFFFD6B2), c400: Color(0xFFD08340),
  c500: Color(0xFFB25C12), c600: Color(0xFF9E4F0F), c700: Color(0xFF83400B), c800: Color(0xFF5E2E07),
  dawn: Color(0xFFC2456F), nightTop: Color(0xFF3A2A1E), nightBottom: Color(0xFF1F1710));

/// Dark ramps are not the light ones inverted: 500 gets lighter so it can carry
/// the page colour as label text, and 200 is a deep tint rather than a pastel.
const brandVioletDark = MemoBrand(
  c50: Color(0xFF1F1A2E), c100: Color(0xFF2A2340), c200: Color(0xFF3B3160), c400: Color(0xFF9B82FF),
  c500: Color(0xFF8C74FF), c600: Color(0xFFA18CFF), c700: Color(0xFFC3B6FF), c800: Color(0xFFDFD7FF),
  dawn: Color(0xFFC2456F), nightTop: Color(0xFF332F7A), nightBottom: Color(0xFF1A1F52));

const brandIndigoDark = MemoBrand(
  c50: Color(0xFF1A1F33), c100: Color(0xFF232B45), c200: Color(0xFF333F6B), c400: Color(0xFF8BA0FF),
  c500: Color(0xFF7D93FF), c600: Color(0xFF9AABFF), c700: Color(0xFFBFC9FF), c800: Color(0xFFDFE4FF),
  dawn: Color(0xFFB84A87), nightTop: Color(0xFF26305E), nightBottom: Color(0xFF161C3C));

const brandTealDark = MemoBrand(
  c50: Color(0xFF14241F), c100: Color(0xFF1B2E28), c200: Color(0xFF274740), c400: Color(0xFF5FCBB2),
  c500: Color(0xFF4FBFA5), c600: Color(0xFF6BD0B8), c700: Color(0xFF9BE0CF), c800: Color(0xFFC8F0E4),
  dawn: Color(0xFFC2603F), nightTop: Color(0xFF1B3A36), nightBottom: Color(0xFF0F2220));

const brandEmberDark = MemoBrand(
  c50: Color(0xFF2A1E14), c100: Color(0xFF33261A), c200: Color(0xFF4A3722), c400: Color(0xFFE09A57),
  c500: Color(0xFFD98A45), c600: Color(0xFFEBA468), c700: Color(0xFFF5C599), c800: Color(0xFFFBE0C4),
  dawn: Color(0xFFC2456F), nightTop: Color(0xFF3A2A1E), nightBottom: Color(0xFF1F1710));

const brandLightRamps = <MemoAccent, MemoBrand>{
  MemoAccent.violet: brandVioletLight, MemoAccent.indigo: brandIndigoLight,
  MemoAccent.teal: brandTealLight, MemoAccent.ember: brandEmberLight,
};

const brandDarkRamps = <MemoAccent, MemoBrand>{
  MemoAccent.violet: brandVioletDark, MemoAccent.indigo: brandIndigoDark,
  MemoAccent.teal: brandTealDark, MemoAccent.ember: brandEmberDark,
};

MemoBrand brandFor(MemoAccent accent, Brightness brightness) =>
  (brightness == Brightness.dark ? brandDarkRamps : brandLightRamps)[accent]!;

/// Whichever of white / [MemoColor.night] reads better on [swatch]. Light-mode
/// 500s are dark enough for white; dark-mode 500s are pastel and need the near
/// black. Picking the larger ratio instead of hard-coding per theme keeps this
/// correct if a ramp is retuned later.
Color inkOn(Color swatch) {
  final luminance = swatch.computeLuminance();
  final white = 1.05 / (luminance + .05);
  final night = (luminance + .05) / (MemoColor.night.computeLuminance() + .05);
  return white >= night ? Colors.white : MemoColor.night;
}

  /// Eight steps, no free-form font sizes. Line heights are pre-baked so text
/// never relies on the default 1.2 that makes Chinese paragraphs look cramped.
///
/// **Three weights, no more.** 400 body, 500 emphasis, 600 headings. The old
/// scale ran w800 on five levels of the same screen, so "bold" stopped meaning
/// anything and every paragraph read as a headline. Weight is a hierarchy
/// signal; spending it everywhere removes the hierarchy.
///
/// **No negative tracking on Chinese.** Latin can take -0.4px at 30px, Han
/// glyphs cannot: their strokes start touching and a bold face turns into a
/// slab. Only the tabular time keeps a little, because digits are narrow.
abstract final class MemoText {
  static const display = TextStyle(fontSize: 30, height: 1.24, fontWeight: FontWeight.w600, color: MemoColor.ink);
  static const title = TextStyle(fontSize: 21, height: 1.3, fontWeight: FontWeight.w600, color: MemoColor.ink);
  static const headline = TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w500, color: MemoColor.ink);
  static const subtitle = TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w500, color: MemoColor.ink);
  static const body = TextStyle(fontSize: 14, height: 1.62, color: MemoColor.ink);
  static const label = TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500, color: MemoColor.inkSoft);
  static const caption = TextStyle(fontSize: 12, height: 1.5, color: MemoColor.muted);
  static const overline = TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: MemoColor.muted);

  /// Buttons: no baked-in colour, so `foregroundColor` from the theme wins.
  static const button = TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500);

  /// The two display numbers. Big enough that the time reads before the text,
  /// which is what makes a list of reminders scannable rather than readable.
  static const heroTime = TextStyle(fontSize: 34, height: 1.08, letterSpacing: -.6,
    fontWeight: FontWeight.w600, color: Color(0xFFFFFFFF), fontFeatures: tabular);
  static const cardTime = TextStyle(fontSize: 21, height: 1.14, letterSpacing: -.2,
    fontWeight: FontWeight.w600, color: MemoColor.ink, fontFeatures: tabular);

  /// Card title: one step above [subtitle], so the clock and the text are not
  /// competing at almost the same size.
  static const cardTitle = TextStyle(fontSize: 15.5, height: 1.5, fontWeight: FontWeight.w500, color: MemoColor.ink);
  static const heroTitle = TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w500, color: Color(0xFFFFFFFF));

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

  /// Brand-tinted lift under the hero card, so it reads as lit rather than cut
  /// out. Takes the colour from the active ramp: a violet shadow under a teal
  /// card looked like a bruise.
  static List<BoxShadow> heroFor(Color brand600) =>
    [BoxShadow(color: brand600.withValues(alpha: .24), blurRadius: 26, offset: const Offset(0, 12))];


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

/// Semantic colours, split from the raw palette so a widget never reads a
/// hex value directly. [light] and [dark] are the only two instances the app
/// ships; anything else is a one-off that will drift.
@immutable
class MemoPalette {
  /// Three surfaces, not two. `canvas` is the page, `surface` is a resting card,
  /// `surfaceAlt` is something lifted off the page (sheets, menus, the selected
  /// swatch frame). In dark mode the three are only ~4% apart in luminance —
  /// enough to read as layers, not enough to glow.
  final Color surface, surfaceAlt, canvas;
  final Color ink, inkSoft, muted, line, lineStrong, outline;
  final Color brand50, brand100, brand200, brand400, brand500, brand600, brand700, brand800;
  final Color onBrand, onBrandSoft, amber, amberSurface, amberInk, amberDeep;
  final Color danger, dangerSurface, success, warning, warningSurface;

  /// The ramp this palette was built from. Kept as one object so the hero card
  /// can pick its gradient stops from the same hue as the accent.
  final MemoBrand brand;
  final MemoAccent accent;

  const MemoPalette({
    required this.surface, required this.canvas, required this.ink, required this.inkSoft,
    required this.muted, required this.line, required this.lineStrong, required this.outline,
    required this.brand50, required this.brand100, required this.brand200, required this.brand400,
    required this.brand500, required this.brand600, required this.brand700, required this.brand800,
    required this.onBrand, required this.onBrandSoft, required this.amber, required this.amberSurface,
    required this.amberInk, required this.amberDeep, required this.danger, required this.dangerSurface,
    required this.success, required this.warning, required this.warningSurface,
    this.surfaceAlt = MemoColor.surfaceAlt,
    this.brand = brandVioletLight, this.accent = MemoAccent.violet,
  });

  /// Same neutrals and semantics, different accent. Used by the appearance
  /// setting; the two const instances below stay the defaults so existing test
  /// assertions keep meaning.
  MemoPalette withBrand(MemoAccent accent, Brightness brightness) {
    final b = brandFor(accent, brightness);
    return MemoPalette(
      surface: surface, surfaceAlt: surfaceAlt, canvas: canvas, ink: ink, inkSoft: inkSoft,
      muted: muted, line: line, lineStrong: lineStrong, outline: outline,
      brand50: b.c50, brand100: b.c100, brand200: b.c200, brand400: b.c400,
      brand500: b.c500, brand600: b.c600, brand700: b.c700, brand800: b.c800,
      onBrand: onBrand, onBrandSoft: onBrandSoft, amber: amber, amberSurface: amberSurface,
      amberInk: amberInk, amberDeep: amberDeep, danger: danger, dangerSurface: dangerSurface,
      success: success, warning: warning, warningSurface: warningSurface,
      brand: b, accent: accent);
  }

  /// 05–10 dawn, 10–17 day, otherwise night. Same three-band idea as before, but
  /// the stops now come from the active ramp.
  List<Color> heroGradientFor(int hour) => hour >= 5 && hour < 10
    ? brand.gradientDawn : hour >= 10 && hour < 17 ? brand.gradientDay : brand.gradientNight;

  static const light = MemoPalette(
    surface: MemoColor.surface, surfaceAlt: MemoColor.surfaceAlt, canvas: MemoColor.canvas,
    ink: MemoColor.ink,
    inkSoft: MemoColor.inkSoft, muted: MemoColor.muted, line: MemoColor.line,
    lineStrong: MemoColor.lineStrong, outline: MemoColor.outline,
    brand50: MemoColor.brand50, brand100: MemoColor.brand100, brand200: MemoColor.brand200,
    brand400: MemoColor.brand400, brand500: MemoColor.brand500, brand600: MemoColor.brand600,
    brand700: MemoColor.brand700, brand800: MemoColor.brand800,
    onBrand: MemoColor.onBrand, onBrandSoft: MemoColor.onBrandSoft,
    amber: MemoColor.amber, amberSurface: MemoColor.amberSurface, amberInk: MemoColor.amberInk,
    amberDeep: MemoColor.amberDeep, danger: MemoColor.danger, dangerSurface: MemoColor.dangerSurface,
    success: MemoColor.success, warning: MemoColor.warning, warningSurface: MemoColor.warningSurface,
  );

  /// Not an inverted light theme: three near-black surfaces with a violet cast
  /// (#0E0D13 page → #191622 card → #221E2D lifted) so the brand does not turn
  /// grey at night, and every text colour clears 4.5:1 against its own surface:
  /// ink 14.4:1, muted 7.1:1, outline 6.2:1 on [surface].
  ///
  /// `ink` used to be #F3EFFA. Dropping four percent of its luminance keeps it
  /// above AAA (14.4:1) while taking the glare off long paragraphs at 2 a.m.
  static const dark = MemoPalette(
    surface: Color(0xFF191622), surfaceAlt: Color(0xFF221E2D), canvas: MemoColor.night,
    ink: Color(0xFFE9E4F4),
    inkSoft: Color(0xFFD9D3E6), muted: Color(0xFFA79FB9), line: Color(0xFF383244),
    lineStrong: Color(0xFF453D55), outline: Color(0xFF928AA6),
    brand50: Color(0xFF1F1A2E), brand100: Color(0xFF2A2340), brand200: Color(0xFF3B3160),
    brand400: Color(0xFF9B82FF), brand500: Color(0xFF8C74FF), brand600: Color(0xFFA18CFF),
    brand700: Color(0xFFC3B6FF), brand800: Color(0xFFDFD7FF),
    onBrand: Color(0xEBFFFFFF), onBrandSoft: Color(0xB8FFFFFF),
    amber: Color(0xFFF0A34F), amberSurface: Color(0xFF35240F), amberInk: Color(0xFFFFD9AC),
    amberDeep: Color(0xFFC9761D), danger: Color(0xFFFF8B80), dangerSurface: Color(0xFF3A1D1B),
    success: Color(0xFF5FD39B), warning: Color(0xFFF0B062), warningSurface: Color(0xFF35240F),
    brand: brandVioletDark,
  );

  /// Palette for a chosen accent. The light and dark bases stay const; only the
  /// ramp is swapped, so neutrals never drift between accents.
  static MemoPalette forAccent(MemoAccent accent, Brightness brightness) =>
    (brightness == Brightness.dark ? dark : light).withBrand(accent, brightness);
}

/// Type scale bound to a palette. Sizes and weights live here; colour comes
/// from the active [MemoPalette], which is why nothing in `lib/` hard-codes a
/// text colour any more.
@immutable
class MemoType {
  final MemoPalette c;
  const MemoType(this.c);

  TextStyle get display => TextStyle(fontSize: 30, height: 1.24, fontWeight: FontWeight.w600, color: c.ink);
  TextStyle get title => TextStyle(fontSize: 21, height: 1.3, fontWeight: FontWeight.w600, color: c.ink);
  TextStyle get headline => TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w500, color: c.ink);
  TextStyle get subtitle => TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w500, color: c.ink);
  TextStyle get body => TextStyle(fontSize: 14, height: 1.62, color: c.ink);
  TextStyle get label => TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500, color: c.inkSoft);
  TextStyle get caption => TextStyle(fontSize: 12, height: 1.5, color: c.muted);
  TextStyle get overline => TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: c.muted);
  TextStyle get button => const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500);
  TextStyle get cardTime => TextStyle(fontSize: 21, height: 1.14, letterSpacing: -.2,
    fontWeight: FontWeight.w600, color: c.ink, fontFeatures: MemoText.tabular);
  TextStyle get cardTitle => TextStyle(fontSize: 15.5, height: 1.5, fontWeight: FontWeight.w500, color: c.ink);

  /// Day-bucket label above a run of cards. It names a range, it is not a
  /// heading: at caption size in [MemoPalette.muted] it reads as a rule on the
  /// page, where ink-weight text used to make the pinned band the brightest
  /// thing on a dark screen.
  TextStyle get groupLabel => TextStyle(fontSize: 12, height: 1.2,
    fontWeight: FontWeight.w500, color: c.muted);

  /// White on the hero gradient in both themes: the card is dark either way.
  TextStyle get heroTime => const TextStyle(fontSize: 34, height: 1.08, letterSpacing: -.6,
    fontWeight: FontWeight.w600, color: Color(0xFFFFFFFF), fontFeatures: MemoText.tabular);
  TextStyle get heroTitle => const TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w500, color: Color(0xFFFFFFFF));
}

/// Theme extension so a future dark theme can swap the whole palette without
/// touching a single widget. Widgets read it through [MemoTokens.of].
@immutable
class MemoTokens extends ThemeExtension<MemoTokens> {
  final MemoPalette colors;
  final MemoType text;

  const MemoTokens({required this.colors, required this.text});

  static const light = MemoTokens(colors: MemoPalette.light, text: MemoType(MemoPalette.light));
  static const dark = MemoTokens(colors: MemoPalette.dark, text: MemoType(MemoPalette.dark));

  /// Tokens for a chosen accent. Rebuilt on every theme change, which happens
  /// once per user action — not per frame.
  static MemoTokens forAccent(MemoAccent accent, Brightness brightness) {
    final palette = MemoPalette.forAccent(accent, brightness);
    return MemoTokens(colors: palette, text: MemoType(palette));
  }

  static MemoTokens of(BuildContext context) =>
    Theme.of(context).extension<MemoTokens>() ?? light;

  @override MemoTokens copyWith({MemoPalette? colors, MemoType? text}) =>
    MemoTokens(colors: colors ?? this.colors, text: text ?? this.text);

  @override MemoTokens lerp(ThemeExtension<MemoTokens>? other, double t) {
    if (other is! MemoTokens) return this;
    if (t < .5) return this;
    return other;
  }
}

/// `context.colors.ink` and `context.type.body` keep call sites short enough
/// that nobody reaches for a raw hex value again.
extension MemoThemeX on BuildContext {
  MemoPalette get colors => MemoTokens.of(this).colors;
  MemoType get text => MemoTokens.of(this).text;
}
