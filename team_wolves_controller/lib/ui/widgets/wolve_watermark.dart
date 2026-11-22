import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'hud_widgets.dart';

/// Geometric low-poly wolf emblem.
///
/// Drawn with plain `Path` polygons so the first run needs no asset file.
/// `assets/wolve_logo.png` can replace it later without touching the rest of
/// the console.
class WolfEmblem extends StatelessWidget {
  const WolfEmblem({
    super.key,
    this.size = 96,
    this.color = TacticalColors.primary,
    this.accent = TacticalColors.amber,
  });

  final double size;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WolfPainter(color: color, accent: accent)),
    );
  }
}

class _WolfPainter extends CustomPainter {
  const _WolfPainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    Offset p(double x, double y) => Offset(x * w, y * h);

    Path poly(List<List<double>> points) {
      final Path path = Path();
      path.moveTo(points[0][0] * w, points[0][1] * h);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i][0] * w, points[i][1] * h);
      }
      path.close();
      return path;
    }

    final Paint fill = Paint()..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.006)
      ..color = color.withA(0.55);

    // Outer head silhouette: ears, brow, cheeks, jaw.
    final Path head = poly(<List<double>>[
      [0.18, 0.06],
      [0.35, 0.02],
      [0.42, 0.24],
      [0.50, 0.20],
      [0.58, 0.24],
      [0.65, 0.02],
      [0.82, 0.06],
      [0.76, 0.34],
      [0.80, 0.48],
      [0.66, 0.70],
      [0.50, 0.94],
      [0.34, 0.70],
      [0.20, 0.48],
      [0.24, 0.34],
    ]);
    canvas.drawPath(head, fill..color = color.withA(0.18));

    // Left and right ear inner facets.
    canvas.drawPath(poly(<List<double>>[
      [0.21, 0.09],
      [0.34, 0.05],
      [0.39, 0.25],
    ]), fill..color = color.withA(0.42));
    canvas.drawPath(poly(<List<double>>[
      [0.79, 0.09],
      [0.66, 0.05],
      [0.61, 0.25],
    ]), fill..color = color.withA(0.30));

    // Brow / forehead plane.
    canvas.drawPath(poly(<List<double>>[
      [0.30, 0.28],
      [0.50, 0.22],
      [0.70, 0.28],
      [0.62, 0.42],
      [0.38, 0.42],
    ]), fill..color = color.withA(0.34));

    // Cheek planes.
    canvas.drawPath(poly(<List<double>>[
      [0.26, 0.34],
      [0.38, 0.42],
      [0.36, 0.66],
      [0.24, 0.48],
    ]), fill..color = color.withA(0.20));
    canvas.drawPath(poly(<List<double>>[
      [0.74, 0.34],
      [0.62, 0.42],
      [0.64, 0.66],
      [0.76, 0.48],
    ]), fill..color = color.withA(0.24));

    // Muzzle.
    canvas.drawPath(poly(<List<double>>[
      [0.38, 0.42],
      [0.62, 0.42],
      [0.58, 0.58],
      [0.50, 0.90],
      [0.42, 0.58],
    ]), fill..color = color.withA(0.12));
    canvas.drawPath(poly(<List<double>>[
      [0.44, 0.58],
      [0.56, 0.58],
      [0.50, 0.86],
    ]), fill..color = color.withA(0.40));

    // Eyes: the only warm accent.
    canvas.drawPath(poly(<List<double>>[
      [0.35, 0.35],
      [0.46, 0.33],
      [0.44, 0.39],
      [0.36, 0.39],
    ]), fill..color = accent);
    canvas.drawPath(poly(<List<double>>[
      [0.65, 0.35],
      [0.54, 0.33],
      [0.56, 0.39],
      [0.64, 0.39],
    ]), fill..color = accent);

    // Nose.
    canvas.drawPath(poly(<List<double>>[
      [0.45, 0.60],
      [0.55, 0.60],
      [0.50, 0.66],
    ]), fill..color = accent.withA(0.85));

    canvas.drawPath(head, stroke);
  }

  @override
  bool shouldRepaint(covariant _WolfPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.accent != accent;
  }
}

/// Non-interactive, low-opacity emblem used behind the console.
class WolveWatermark extends StatelessWidget {
  const WolveWatermark({super.key, this.opacity = 0.11});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Center(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double extent = math.min(constraints.maxWidth, constraints.maxHeight);
              return WolfEmblem(
                size: extent.isFinite ? extent * 0.62 : 240.0,
                color: TacticalColors.primary,
                accent: TacticalColors.amber,
              );
            },
          ),
        ),
      ),
    );
  }
}
