import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// The single surface primitive: hairline border, one soft shadow, optional tap
/// with a real ink response. Every card-like block in the app is built from it.
///
/// Tappable cards also dip 2.2% and tighten their shadow under the finger. Both
/// are implicit animations, so they settle into a static `Transform` and stop
/// ticking the moment the finger lifts — nothing here animates on its own.
class MemoCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final bool border;
  final bool shadow;

  /// Selection state for batch mode: a brand outline instead of the hairline,
  /// and a tinted fill. Cheaper than a second widget stacked on top, and it
  /// keeps the card's own padding and shadow untouched.
  final bool selected;

  const MemoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MemoSpace.xl),
    this.radius = MemoRadius.xl,
    this.onTap,
    this.onLongPress,
    this.color,
    this.border = true,
    this.shadow = true,
    this.selected = false,
  });

  @override State<MemoCard> createState() => _MemoCardState();
}

class _MemoCardState extends State<MemoCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.radius),
      side: widget.selected ?  BorderSide(color: context.colors.brand600, width: 1.6)
        : widget.border ?  BorderSide(color: context.colors.line) : BorderSide.none,
    );
    final content = widget.padding == EdgeInsets.zero
      ? widget.child : Padding(padding: widget.padding, child: widget.child);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: !widget.shadow ? null : (_pressed ? MemoShadow.press : MemoShadow.card),
      ),
      // The scale sits *inside* the decorated box on purpose. `RenderTransform`
      // never adds itself to a hit-test result, so making it the card's root
      // would make `tester.tap(find.byKey(...))` report a miss, and any tooling
      // that walks the hit path would lose the card.
      child: AnimatedScale(
        scale: _pressed ? MemoMotion.pressScale : 1,
        duration: MemoMotion.press,
        curve: MemoMotion.curve,
        child: Material(
          color: widget.color ?? (widget.selected ? context.colors.brand50 : context.colors.surface),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: widget.onTap == null && widget.onLongPress == null
            ? content
            : InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                customBorder: shape,
                onHighlightChanged: (v) { if (v != _pressed) setState(() => _pressed = v); },
                child: content),
        ),
      ),
    );
  }
}

/// What a state chip is allowed to mean.
///
/// The list used to fold every fact into one grey sentence — "每天 · 语音就绪"
/// read exactly like "明天", even though one is a rule and the other is a time.
/// Colour is the cheapest way to separate kinds of fact without adding rows:
/// five tones, each mapped to a palette pair that clears 4.5:1 on its own tint.
enum MemoTagTone {
  /// A rule that will fire again: repeat schedules, counts.
  brand,
  /// Something is moving and the user may want to wait for it.
  warning,
  /// A finished, healthy state — audio ready, and nothing else.
  success,
  /// Something needs attention: a failed render.
  danger,
  /// Structural state with no urgency: paused, ended, missing audio.
  neutral,
}

/// Inline status chip. One shape, five tints.
class MemoTag extends StatelessWidget {
  final String text;
  final bool emphasized;
  final MemoTagTone tone;
  final IconData? icon;
  const MemoTag(this.text, {super.key, this.emphasized = false,
    this.tone = MemoTagTone.brand, this.icon});

  @override
  Widget build(BuildContext context) {
    // The unread chip is the only solid fill in the list. On a dark page the
    // deep amber does not carry white text any more (#C9761D caps at 3.0:1),
    // so the fill lightens and the label flips to the page colour — 8.7:1.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (background, foreground) = switch (tone) {
      MemoTagTone.brand => (context.colors.brand100, context.colors.brand700),
      MemoTagTone.warning => (context.colors.warningSurface, context.colors.warning),
      MemoTagTone.success => (context.colors.successSurface, context.colors.success),
      MemoTagTone.danger => (context.colors.dangerSurface, context.colors.danger),
      MemoTagTone.neutral => (context.colors.line, context.colors.muted),
    };
    final fill = emphasized
      ? (dark ? context.colors.amber : context.colors.amberDeep) : background;
    final ink = emphasized
      ? (dark ? context.colors.canvas : Colors.white) : foreground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MemoSpace.sm, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(MemoRadius.sm),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: ink),
          const SizedBox(width: 3),
        ],
        // Flexible so a long label truncates instead of overflowing the row;
        // the chip row itself wraps, this is the last line of defence.
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: context.text.overline.copyWith(color: ink, height: 1.35))),
      ]),
    );
  }
}

/// Permission / status strip that leads somewhere. Tinted surface, not a shadow.
class MemoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? background, foreground;
  final VoidCallback? onTap;

  const MemoBanner({
    super.key,
    required this.icon,
    required this.text,
    this.background,
    this.foreground,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(MemoRadius.lg);
    final tint = background ?? context.colors.warningSurface;
    final inkOnTint = foreground ?? context.colors.warning;
    return Material(
      color: tint,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(children: [
            Icon(icon, color: inkOnTint, size: 20),
            const SizedBox(width: MemoSpace.md),
            Expanded(child: Text(text, style: context.text.label.copyWith(color: context.colors.ink))),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: inkOnTint, size: 20),
          ]),
        ),
      ),
    );
  }
}
