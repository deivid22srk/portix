import 'package:flutter/material.dart';

import '../../app/theme.dart';

// Marca do PORTIX: um portal aberto com um núcleo de luz.
// Desenhada em código para ficar idêntica em qualquer densidade.
class PortixMark extends StatelessWidget {
  const PortixMark({super.key, this.size = 40, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PortixMarkPainter(glow: glow)),
    );
  }
}

class _PortixMarkPainter extends CustomPainter {
  const _PortixMarkPainter({required this.glow});

  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double s = size.shortestSide;
    final Offset center = rect.center;

    if (glow) {
      final Paint halo = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            AppPalette.violet.withValues(alpha: 0.30),
            AppPalette.cyan.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const <double>[0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: s * 0.52));
      canvas.drawCircle(center, s * 0.52, halo);
    }

    final RRect outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.15, s * 0.10, s * 0.70, s * 0.78),
      Radius.circular(s * 0.30),
    );
    final RRect inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.31, s * 0.30, s * 0.38, s * 0.70),
      Radius.circular(s * 0.17),
    );
    final Path arch = Path.combine(
      PathOperation.difference,
      Path()..addRRect(outer),
      Path()..addRRect(inner),
    );
    final Paint archPaint = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Colors.white, Color(0xFFD8DDFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawPath(arch, archPaint);

    final Offset orbCenter = Offset(s * 0.50, s * 0.42);
    final double orbRadius = s * 0.105;
    final Paint orbHalo = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppPalette.cyan.withValues(alpha: 0.55),
          AppPalette.violet.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: orbCenter, radius: orbRadius * 2.4));
    canvas.drawCircle(orbCenter, orbRadius * 2.4, orbHalo);

    final Paint orb = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[AppPalette.cyan, AppPalette.violet],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: orbCenter, radius: orbRadius));
    canvas.drawCircle(orbCenter, orbRadius, orb);
  }

  @override
  bool shouldRepaint(covariant _PortixMarkPainter oldDelegate) =>
      oldDelegate.glow != glow;
}

class PortixWordmark extends StatelessWidget {
  const PortixWordmark({super.key, this.markSize = 30, this.fontSize = 22});

  final double markSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PortixMark(size: markSize),
        const SizedBox(width: 10),
        Text(
          'PORTIX',
          style: context.texts.titleLarge?.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 3.4,
            color: p.text,
          ),
        ),
      ],
    );
  }
}
