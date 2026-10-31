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
      // Two transforms, both cheap: `RenderTransform` scales the matrix and
      // `RenderOpacity` fades the layer. Once `t` hits 1 the tree collapses to
      // `child` with no wrapper at all, so a settled list pays nothing.
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * shift),
          child: Transform.scale(
            scale: MemoMotion.enterScale + (1 - MemoMotion.enterScale) * t,
            alignment: Alignment.center,
            child: c,
          ),
        ),
      );
    },
    child: child,
  );
}

/// Swaps a run of text on change, sliding the new value up from under the old
/// one. Used for the hero clock: when the next reminder changes, the number
/// travels 8px instead of blinking, which is the difference between "the list
/// updated" and "the list jumped".
///
/// The old child is only in the tree during the 180ms overlap, so there is no
/// steady-state cost. Widths differ between values, so the stack is aligned
/// left and the caller is expected to place it where the text can grow.
class MemoNumberSwap extends StatelessWidget {
  final String value;
  final TextStyle? style;
  final TextAlign textAlign;
  final int maxLines;

  const MemoNumberSwap(this.value, {super.key, this.style, this.textAlign = TextAlign.start, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MemoMotion.number,
    switchInCurve: MemoMotion.curve,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.centerLeft,
      children: [...previous, if (current != null) current],
    ),
    transitionBuilder: (child, animation) {
      final slide = Tween<Offset>(begin: const Offset(0, .38), end: Offset.zero)
        .animate(CurvedAnimation(parent: animation, curve: MemoMotion.curve));
      return ClipRect(child: FadeTransition(
        opacity: animation,
        child: SlideTransition(position: slide, child: child)));
    },
    child: Text(value, key: ValueKey(value), style: style, textAlign: textAlign,
      maxLines: maxLines, overflow: TextOverflow.ellipsis),
  );
}

/// Scroll behaviour for the whole app: iOS physics everywhere, and no Android
/// stretch glow on top of it. The decorative stretch indicator and a bouncing
/// edge fight each other — one pushes the content, the other lets it run.
class MemoScrollBehavior extends MaterialScrollBehavior {
  const MemoScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
    const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
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
