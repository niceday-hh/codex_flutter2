import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Empty-state illustration: a note card, three lines, a small bell.
///
/// Drawn with paths rather than shipped as an asset — no bundle weight, no
/// second copy for 3×, and every colour comes from the active palette so the
/// drawing flips with the theme instead of glowing white on a dark page.
class MemoEmptyArt extends StatelessWidget {
  final double size;
  const MemoEmptyArt({super.key, this.size = 148});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size * .78,
    child: CustomPaint(painter: _EmptyArtPainter(context.colors)),
  );
}

class _EmptyArtPainter extends CustomPainter {
  final MemoPalette c;
  const _EmptyArtPainter(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    canvas.drawCircle(Offset(w * .46, h * .54), w * .34, Paint()..color = c.brand100);
    canvas.drawCircle(Offset(w * .78, h * .24), w * .085, Paint()..color = c.amberSurface);

    final note = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * .46, h * .54), width: w * .44, height: h * .54),
      Radius.circular(w * .05));

    canvas.save();
    canvas.translate(w * .46, h * .54);
    canvas.rotate(-.055);
    canvas.translate(-w * .46, -h * .54);
    canvas.drawRRect(note, Paint()..color = c.surface);
    canvas.drawRRect(note, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = c.lineStrong);
    final rule = Paint()
      ..color = c.lineStrong
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = note.top + note.height * (.30 + i * .19);
      final right = i == 2 ? note.left + note.width * .62 : note.right - note.width * .16;
      canvas.drawLine(Offset(note.left + note.width * .16, y), Offset(right, y), rule);
    }
    canvas.restore();

    // A bell, not a dome on a stick: body, base line, clapper.
    final bell = Offset(w * .74, h * .33);
    final bellStroke = Paint()
      ..color = c.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final r = w * .072;
    final body = Path()
      ..moveTo(bell.dx - r, bell.dy + r * .62)
      ..lineTo(bell.dx - r, bell.dy + r * .08)
      ..arcToPoint(Offset(bell.dx + r, bell.dy + r * .08), radius: Radius.circular(r), clockwise: true)
      ..lineTo(bell.dx + r, bell.dy + r * .62);
    canvas.drawPath(body, bellStroke);
    canvas.drawLine(Offset(bell.dx - r * 1.1, bell.dy + r * .62),
      Offset(bell.dx + r * 1.1, bell.dy + r * .62), bellStroke);
    canvas.drawCircle(Offset(bell.dx, bell.dy + r * .95), r * .17, Paint()..color = c.amber);
  }

  @override
  bool shouldRepaint(_EmptyArtPainter oldDelegate) => !identical(oldDelegate.c, c);
}
