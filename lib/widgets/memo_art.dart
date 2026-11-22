import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Visual variant for [MemoEmptyArt]. Defaults to [upcoming] to preserve
/// existing call sites.
enum MemoEmptyKind { upcoming, history, search }

/// Empty-state illustration: a note card, three lines, and a contextual emblem.
class MemoEmptyArt extends StatelessWidget {
  final double size;
  final MemoEmptyKind kind;

  const MemoEmptyArt({
    super.key,
    this.size = 148,
    this.kind = MemoEmptyKind.upcoming,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * .78,
    child: CustomPaint(painter: _EmptyArtPainter(context.colors, kind)),
  );
}

class _EmptyArtPainter extends CustomPainter {
  final MemoPalette c;
  final MemoEmptyKind kind;
  const _EmptyArtPainter(this.c, this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    canvas.drawCircle(
      Offset(w * .46, h * .54),
      w * .34,
      Paint()..color = c.brand100,
    );
    canvas.drawCircle(
      Offset(w * .78, h * .24),
      w * .085,
      Paint()..color = kind == MemoEmptyKind.search ? c.brand100 : c.amberSurface,
    );

    final note = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * .46, h * .54),
        width: w * .44,
        height: h * .54,
      ),
      Radius.circular(w * .05),
    );

    canvas.save();
    canvas.translate(w * .46, h * .54);
    canvas.rotate(kind == MemoEmptyKind.history ? .035 : -.055);
    canvas.translate(-w * .46, -h * .54);
    canvas.drawRRect(note, Paint()..color = c.surface);
    canvas.drawRRect(
      note,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = c.lineStrong,
    );
    final rule = Paint()
      ..color = c.lineStrong
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = note.top + note.height * (.30 + i * .19);
      final right = i == 2
          ? note.left + note.width * .62
          : note.right - note.width * .16;
      canvas.drawLine(Offset(note.left + note.width * .16, y), Offset(right, y), rule);
    }
    canvas.restore();

    final badgeCenter = Offset(w * .74, h * .33);
    final r = w * .072;
    switch (kind) {
      case MemoEmptyKind.upcoming:
        _drawBell(canvas, badgeCenter, r);
      case MemoEmptyKind.history:
        _drawCheck(canvas, badgeCenter, r);
      case MemoEmptyKind.search:
        _drawMagnifier(canvas, badgeCenter, r);
    }
  }

  void _drawBell(Canvas canvas, Offset bell, double r) {
    final bellStroke = Paint()
      ..color = c.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final body = Path()
      ..moveTo(bell.dx - r, bell.dy + r * .62)
      ..lineTo(bell.dx - r, bell.dy + r * .08)
      ..arcToPoint(
        Offset(bell.dx + r, bell.dy + r * .08),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..lineTo(bell.dx + r, bell.dy + r * .62);
    canvas.drawPath(body, bellStroke);
    canvas.drawLine(
      Offset(bell.dx - r * 1.1, bell.dy + r * .62),
      Offset(bell.dx + r * 1.1, bell.dy + r * .62),
      bellStroke,
    );
    canvas.drawCircle(
      Offset(bell.dx, bell.dy + r * .95),
      r * .17,
      Paint()..color = c.amber,
    );
  }

  void _drawCheck(Canvas canvas, Offset center, double r) {
    final stroke = Paint()
      ..color = c.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(center, r * 1.05, stroke);
    final tick = Path()
      ..moveTo(center.dx - r * .46, center.dy + r * .04)
      ..lineTo(center.dx - r * .10, center.dy + r * .40)
      ..lineTo(center.dx + r * .52, center.dy - r * .34);
    canvas.drawPath(tick, stroke);
  }

  void _drawMagnifier(Canvas canvas, Offset center, double r) {
    final stroke = Paint()
      ..color = c.brand500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(center.dx - r * .15, center.dy - r * .15), r * .85, stroke);
    canvas.drawLine(
      Offset(center.dx + r * .45, center.dy + r * .45),
      Offset(center.dx + r * 1.05, center.dy + r * 1.05),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_EmptyArtPainter oldDelegate) =>
      !identical(oldDelegate.c, c) || oldDelegate.kind != kind;
}
