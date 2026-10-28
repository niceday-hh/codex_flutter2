import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// The single surface primitive: hairline border, one soft shadow, optional tap
/// with a real ink response. Every card-like block in the app is built from it.
class MemoCard extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ? const BorderSide(color: MemoColor.line) : BorderSide.none,
    );
    final content = padding == EdgeInsets.zero ? child : Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? MemoShadow.card : null,
      ),
      child: Material(
        color: color ?? MemoColor.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
          ? content
          : InkWell(onTap: onTap, customBorder: shape, child: content),
      ),
    );
  }
}

/// Inline status chip. One shape, one tint, one text colour.
class MemoTag extends StatelessWidget {
  final String text;
  final bool emphasized;
  const MemoTag(this.text, {super.key, this.emphasized = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: MemoSpace.sm, vertical: 3),
    decoration: BoxDecoration(
      color: emphasized ? MemoColor.brand500 : MemoColor.brand100,
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
