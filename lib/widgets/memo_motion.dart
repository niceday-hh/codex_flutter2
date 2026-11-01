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

/// Two static brand washes behind a page — one above the header on the right,
/// one low on the left, so the canvas has a direction instead of a single halo
/// pinned to the top edge.
///
/// Both are painted inside one [RepaintBoundary]: the pair costs one fill on
/// first layout and nothing at all while the list scrolls. The colours come
/// from the active ramp, so switching to 青碧 does not leave a violet cloud
/// behind a green card.
class MemoGlow extends StatelessWidget {
  final Widget child;
  const MemoGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Sits behind the header icons, not behind the title: the top-left is
          // where the 34px serif starts and a wash there would grey it out.
          Positioned(top: -170, right: -110, child: _blob(c.brand500.withValues(alpha: .10), 380)),
          Positioned(top: 260, left: -150, child: _blob(c.brand400.withValues(alpha: .06), 340)),
        ])))),
      child,
    ]);
  }

  Widget _blob(Color color, double size) => Container(width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])));
}
