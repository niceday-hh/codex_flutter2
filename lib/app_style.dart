import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Backwards-compatible names for the palette. New code should read
/// [MemoColor] / [MemoText] directly; these aliases exist so older call sites
/// keep compiling while they are migrated.
const purple = MemoColor.brand500;
const ink = MemoColor.ink;
const muted = MemoColor.muted;
const canvas = MemoColor.canvas;
const lavender = MemoColor.brand100;
const brandInk = MemoColor.brand700;
const line = MemoColor.line;
const success = MemoColor.success;
const warning = MemoColor.warning;
const danger = MemoColor.danger;
const tabularFigures = MemoText.tabular;

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
    Expanded(child: Text(message, style: MemoText.body.copyWith(
      fontSize: 13.5, height: 1.45, color: Colors.white))),
  ]),
);
