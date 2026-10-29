import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// App-wide snack bar: one shape, one rhythm, a leading state icon.
/// The message stays a plain [Text] so existing finders keep working.
SnackBar memoSnackBar(String message, {bool error = false}) => SnackBar(
  behavior: SnackBarBehavior.floating,
  backgroundColor: const Color(0xFF211D33),
  elevation: 0,
  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
  duration: Duration(seconds: error ? 5 : 3),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MemoRadius.md)),
  content: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
      size: 20, color: error ? const Color(0xFFFFB4A8) : const Color(0xFF9BE3C4)),
    const SizedBox(width: 10),
    Expanded(child: Text(message, style: const TextStyle(
      fontSize: 13.5, height: 1.45, color: Colors.white))),
  ]),
);
