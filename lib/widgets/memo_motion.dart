import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Entrance wrapper: fade + a short upward drift, driven by an [Animation] the
/// page owns so the whole list shares one controller (one ticker, not N).
class MemoReveal extends StatelessWidget {
  final Animation<double> animation;
  final double shift;
  final Widget child;

  const MemoReveal({
    super.key,
    required this.animation,
    this.shift = MemoMotion.enterShift,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, c) {
      final t = animation.value;
      if (t >= 1) return c!;
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

/// Swaps a run of text on change, sliding the new value in from [direction]
/// (`>= 0` slides upward from below, `< 0` slides downward from above).
class MemoNumberSwap extends StatelessWidget {
  final String value;
  final TextStyle? style;
  final TextAlign textAlign;
  final int maxLines;
  final int direction;

  const MemoNumberSwap(
    this.value, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.direction = 1,
  });

  @override
  Widget build(BuildContext context) {
    final dy = direction >= 0 ? 0.38 : -0.38;
    return AnimatedSwitcher(
      duration: MemoMotion.number,
      switchInCurve: MemoMotion.curve,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == ValueKey(value);
        final beginOffset = Offset(0, isIncoming ? dy : -dy * 0.6);
        final slide = Tween<Offset>(begin: beginOffset, end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: MemoMotion.curve));
        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          ),
        );
      },
      child: Text(
        value,
        key: ValueKey(value),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Scroll behaviour for the whole app: iOS physics everywhere, and no Android
/// stretch glow on top of it.
class MemoScrollBehavior extends MaterialScrollBehavior {
  const MemoScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Two static brand washes behind a page painted inside one [RepaintBoundary].
class MemoGlow extends StatelessWidget {
  final Widget child;
  const MemoGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  top: -170,
                  right: -110,
                  child: _blob(c.brand500.withValues(alpha: .10), 380),
                ),
                Positioned(
                  top: 260,
                  left: -150,
                  child: _blob(c.brand400.withValues(alpha: .06), 340),
                ),
              ],
            ),
          ),
        ),
      ),
      child,
    ]);
  }

  Widget _blob(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}
