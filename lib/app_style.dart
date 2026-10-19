import 'dart:ui';
import 'package:flutter/material.dart';

const purple = Color(0xFF7252F6);
const ink = Color(0xFF25213A);
const muted = Color(0xFF8A859C);
const canvas = Color(0xFFF8F6FC);
const lavender = Color(0xFFF0ECFF);

class FrostedPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  const FrostedPanel({super.key, required this.child, this.radius = 30});
  @override Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: [
      BoxShadow(color: ink.withValues(alpha: .09), blurRadius: 36, offset: const Offset(0, 12)),
    ]),
    child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: .97), const Color(0xFFF9F7FF).withValues(alpha: .93)]),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: .85))), child: child))));
}
