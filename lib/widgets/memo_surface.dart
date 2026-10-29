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
  final Color? color;
  final bool border;
  final bool shadow;

  const MemoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MemoSpace.xl),
    this.radius = MemoRadius.xl,
    this.onTap,
    this.color,
    this.border = true,
    this.shadow = true,
  });

  @override State<MemoCard> createState() => _MemoCardState();
}

class _MemoCardState extends State<MemoCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.radius),
      side: widget.border ? const BorderSide(color: MemoColor.line) : BorderSide.none,
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
          color: widget.color ?? MemoColor.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: widget.onTap == null
            ? content
            : InkWell(
                onTap: widget.onTap,
                customBorder: shape,
                onHighlightChanged: (v) { if (v != _pressed) setState(() => _pressed = v); },
                child: content),
        ),
      ),
    );
  }
}

/// Inline status chip. One shape, two tints: brand for routine state, amber for
/// "unread", so the chip and the card's left bar speak the same colour language.
class MemoTag extends StatelessWidget {
  final String text;
  final bool emphasized;
  const MemoTag(this.text, {super.key, this.emphasized = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: MemoSpace.sm, vertical: 3),
    decoration: BoxDecoration(
      color: emphasized ? MemoColor.amberDeep : MemoColor.brand100,
      borderRadius: BorderRadius.circular(MemoRadius.sm),
    ),
    child: Text(text, style: MemoText.overline.copyWith(
      color: emphasized ? Colors.white : MemoColor.brand700, height: 1.35)),
  );
}

/// Permission / status strip that leads somewhere. Tinted surface, not a shadow.
class MemoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color background, foreground;
  final VoidCallback? onTap;

  const MemoBanner({
    super.key,
    required this.icon,
    required this.text,
    this.background = MemoColor.warningSurface,
    this.foreground = MemoColor.warning,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(MemoRadius.lg);
    return Material(
      color: background,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: MemoSpace.md),
            Expanded(child: Text(text, style: MemoText.label.copyWith(color: MemoColor.ink))),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: foreground, size: 20),
          ]),
        ),
      ),
    );
  }
}
