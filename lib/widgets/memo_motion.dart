import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Entrance wrapper: fade + a short upward drift, driven by an [Animation] the
/// page owns so the whole list shares one controller (one ticker, not N).
///
/// At t == 1 the widget tree collapses to zero cost: `RenderOpacity` skips the
/// layer at full alpha and `RenderTransform` skips the matrix at identity, so a
/// settled list paints exactly like before this widget existed.
class MemoReveal extends StatelessWidget {
  final Animation<double> animation;
  final double shift;
  final Widget child;

  const MemoReveal({super.key, required this.animation, this.shift = MemoMotion.enterShift, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, c) {
      final t = animation.value;
      if (t >= 1) return c!;
      return Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * shift), child: c),
      );
    },
    child: child,
  );
}

/// Static brand wash behind a page. `RepaintBoundary` keeps it out of every
/// scroll-driven repaint, so the whole effect costs one fill on first layout.
class MemoGlow extends StatelessWidget {
  final Widget child;
  const MemoGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: DecoratedBox(
        decoration: const BoxDecoration(gradient: RadialGradient(
          center: Alignment(0, -1.18),
          radius: 1.0,
          colors: [MemoColor.glowCore, MemoColor.glowEdge],
          stops: [0, .78],
        )),
      )))),
      child,
    ],
  );
}
