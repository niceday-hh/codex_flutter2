import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// App-wide snack bar: one shape, one rhythm, a leading state icon.
///
/// Pass [palette] to align the snack bar surface and border with the active
/// [MemoPalette]. Omitting [palette] preserves the default dark surface so
/// existing callers and widget tests keep working.
/// The message stays a plain [Text] so existing finders keep working.
SnackBar memoSnackBar(
  String message, {
  bool error = false,
  MemoPalette? palette,
}) {
  final isDark = palette != null && palette.surface.computeLuminance() < 0.2;
  final bg = palette == null
      ? const Color(0xFF211D33)
      : (isDark ? palette.surfaceAlt : palette.ink);
  final fg = palette == null
      ? Colors.white
      : (isDark ? palette.ink : palette.surface);
  final border = palette == null
      ? Colors.white.withValues(alpha: 0.08)
      : (isDark
          ? Colors.white.withValues(alpha: 0.10)
          : palette.brand400.withValues(alpha: 0.18));
  final iconColor = error
      ? (isDark ? palette.danger : const Color(0xFFFFB4A8))
      : (isDark ? palette.success : const Color(0xFF9BE3C4));

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: bg,
    elevation: 0,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    duration: Duration(seconds: error ? 5 : 3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MemoRadius.md),
      side: BorderSide(color: border, width: 1),
    ),
    content: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(
        error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
        size: 20,
        color: iconColor,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          message,
          style: TextStyle(fontSize: 13.5, height: 1.45, color: fg),
        ),
      ),
    ]),
  );
}
