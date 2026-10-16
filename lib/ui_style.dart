import 'package:flutter/material.dart';

abstract final class X5Style {
  static const text = Color(0xffe1e2d9);
  static const muted = Color(0xff989b90);
  static const accent = Color(0xffaaa68e);
  static const background = Color(0xbf0d0e0c);
  static const surface = Color(0xbf1b1d18);
  static const mobileBackground = Color(0xff343631);
  static const mobileSurface = Color(0xff20221d);
  static const mobileCanvas = Color(0xff242621);
  static const border = Color(0xff45463e);
  static const radius = BorderRadius.all(Radius.circular(11));
  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'RobotoCondensed',
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    sliderTheme: const SliderThemeData(
      showValueIndicator: ShowValueIndicator.never,
    ),
    useMaterial3: true,
  );
  static const bloom = [
    Shadow(color: Color(0xbfffffff), blurRadius: 3),
    Shadow(color: Color(0x66ffffff), blurRadius: 8),
  ];
}

enum X5Glyph {
  thermometer,
  power,
  minus,
  plus,
  cold,
  auto,
  dry,
  fan,
  moon,
  swing,
  shield,
  settings,
  eye,
  wifi,
  key,
  back,
}

class X5Icon extends StatelessWidget {
  final X5Glyph glyph;
  final double size;
  final Color color;
  final bool glow;
  const X5Icon(
    this.glyph, {
    super.key,
    this.size = 24,
    this.color = X5Style.accent,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: glyph == X5Glyph.swing ? size * 1.4 : size,
    height: size,
    child: CustomPaint(painter: _IconPainter(glyph, color, glow)),
  );
}

class X5IconButton extends StatelessWidget {
  final String label;
  final X5Glyph glyph;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final double extent;
  final Color? background;
  const X5IconButton({
    super.key,
    required this.label,
    required this.glyph,
    required this.onPressed,
    this.active = false,
    this.size = 20,
    this.extent = 44,
    this.background,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    enabled: onPressed != null,
    child: SizedBox.square(
      dimension: extent,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: extent, height: extent),
        style: IconButton.styleFrom(
          backgroundColor: background ?? Colors.transparent,
          hoverColor: Colors.white.withAlpha(8),
          disabledBackgroundColor: background ?? Colors.transparent,
        ),
        icon: X5Icon(
          glyph,
          size: size,
          glow: active,
          color:
              active
                  ? Colors.white
                  : onPressed == null
                  ? X5Style.muted.withAlpha(100)
                  : X5Style.accent,
        ),
      ),
    ),
  );
}

class _IconPainter extends CustomPainter {
  final X5Glyph glyph;
  final Color color;
  final bool glow;
  const _IconPainter(this.glyph, this.color, this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(
      size.width / (glyph == X5Glyph.swing ? 34 : 24),
      size.height / 24,
    );
    final p = Path();
    void circle(double x, double y, double r) =>
        p.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
    switch (glyph) {
      case X5Glyph.thermometer:
        p.moveTo(9, 14.5);
        p.lineTo(9, 5);
        p.cubicTo(9, 1, 15, 1, 15, 5);
        p.lineTo(15, 14.5);
        p.cubicTo(21, 19, 15, 25, 10, 22);
        p.cubicTo(6, 20, 6, 17, 9, 14.5);
        p.moveTo(12, 7);
        p.lineTo(12, 17);
        circle(12, 18, 1.5);
      case X5Glyph.power:
        p.moveTo(12, 3);
        p.lineTo(12, 11);
        p.moveTo(6.3, 5.7);
        p.cubicTo(-1, 12, 5, 22, 12, 21);
        p.cubicTo(20, 21, 25, 12, 17.7, 5.7);
      case X5Glyph.minus:
        p.moveTo(5, 12);
        p.lineTo(19, 12);
      case X5Glyph.plus:
        p.moveTo(5, 12);
        p.lineTo(19, 12);
        p.moveTo(12, 5);
        p.lineTo(12, 19);
      case X5Glyph.cold:
        p.moveTo(12, 2);
        p.lineTo(12, 22);
        p.moveTo(3.3, 7);
        p.lineTo(20.7, 17);
        p.moveTo(3.3, 17);
        p.lineTo(20.7, 7);
        p.moveTo(9, 4);
        p.lineTo(12, 7);
        p.lineTo(15, 4);
        p.moveTo(9, 20);
        p.lineTo(12, 17);
        p.lineTo(15, 20);
        p.moveTo(4, 10);
        p.lineTo(8, 9);
        p.lineTo(7, 5);
        p.moveTo(20, 14);
        p.lineTo(16, 15);
        p.lineTo(17, 19);
        p.moveTo(4, 14);
        p.lineTo(8, 15);
        p.lineTo(7, 19);
        p.moveTo(20, 10);
        p.lineTo(16, 9);
        p.lineTo(17, 5);
      case X5Glyph.auto:
        p.moveTo(4, 9);
        p.cubicTo(6, 1, 15, 1, 20, 8);
        p.moveTo(20, 4);
        p.lineTo(20, 8);
        p.lineTo(16, 8);
        p.moveTo(20, 15);
        p.cubicTo(18, 23, 9, 23, 4, 16);
        p.moveTo(4, 20);
        p.lineTo(4, 16);
        p.lineTo(8, 16);
        p.moveTo(9, 15);
        p.lineTo(12, 8);
        p.lineTo(15, 15);
        p.moveTo(10, 12.5);
        p.lineTo(14, 12.5);
      case X5Glyph.dry:
        p.moveTo(12, 2);
        p.cubicTo(12, 2, 5, 10, 5, 15);
        p.cubicTo(5, 24, 19, 24, 19, 15);
        p.cubicTo(19, 10, 12, 2, 12, 2);
        p.moveTo(8, 15);
        p.quadraticBezierTo(8, 19, 12, 19);
      case X5Glyph.fan:
        circle(12, 12, 2);
        p.moveTo(12, 10);
        p.cubicTo(9, 7, 11, 2, 14, 2);
        p.cubicTo(19, 2, 19, 8, 14, 11);
        p.moveTo(14, 12);
        p.cubicTo(17, 9, 22, 11, 22, 14);
        p.cubicTo(22, 19, 16, 19, 13, 14);
        p.moveTo(12, 14);
        p.cubicTo(15, 17, 13, 22, 10, 22);
        p.cubicTo(5, 22, 5, 16, 10, 13);
        p.moveTo(10, 12);
        p.cubicTo(7, 15, 2, 13, 2, 10);
        p.cubicTo(2, 5, 8, 5, 11, 10);
      case X5Glyph.moon:
        p.moveTo(20.5, 14);
        p.cubicTo(12, 17, 7, 11, 10, 3.5);
        p.cubicTo(-4, 8, 3, 27, 16, 21);
        p.quadraticBezierTo(20, 19, 20.5, 14);
      case X5Glyph.swing:
        p.addRRect(
          RRect.fromRectAndCorners(
            const Rect.fromLTWH(1, 8, 24, 8.5),
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2),
            bottomLeft: const Radius.circular(3),
            bottomRight: const Radius.circular(3),
          ),
        );
        p.moveTo(1.5, 13.5);
        p.lineTo(24.5, 13.5);
        p.moveTo(3, 15);
        p.lineTo(23, 15);
        p.moveTo(20.5, 11.5);
        p.lineTo(23, 11.5);
        p.moveTo(30, 8);
        p.lineTo(30, 16.5);
        p.moveTo(27.5, 10.5);
        p.lineTo(30, 8);
        p.lineTo(32.5, 10.5);
        p.moveTo(27.5, 14);
        p.lineTo(30, 16.5);
        p.lineTo(32.5, 14);
      case X5Glyph.shield:
        p.moveTo(12, 3);
        p.lineTo(19, 6);
        p.lineTo(19, 12);
        p.cubicTo(19, 16, 15, 19, 12, 21);
        p.cubicTo(9, 19, 5, 16, 5, 12);
        p.lineTo(5, 6);
        p.close();
        p.moveTo(8, 12);
        p.lineTo(11, 15);
        p.lineTo(16, 9);
      case X5Glyph.settings:
        for (final row in [(6.0, 13.0), (12.0, 8.0), (18.0, 16.0)]) {
          p.moveTo(3, row.$1);
          p.lineTo(row.$2 - 2, row.$1);
          p.moveTo(row.$2 + 2, row.$1);
          p.lineTo(21, row.$1);
          circle(row.$2, row.$1, 2);
        }
      case X5Glyph.eye:
        p.moveTo(2, 12);
        p.cubicTo(6, 3, 18, 3, 22, 12);
        p.cubicTo(18, 21, 6, 21, 2, 12);
        circle(12, 12, 3);
      case X5Glyph.wifi:
        p.moveTo(3, 8);
        p.quadraticBezierTo(12, 1.5, 21, 8);
        p.moveTo(6, 12);
        p.quadraticBezierTo(12, 7.5, 18, 12);
        p.moveTo(9, 16);
        p.quadraticBezierTo(12, 13.5, 15, 16);
        circle(12, 20, .5);
      case X5Glyph.key:
        circle(7, 11, 4.5);
        p.moveTo(11.5, 11);
        p.lineTo(22, 11);
        p.moveTo(17, 11);
        p.lineTo(17, 15);
        p.moveTo(21, 11);
        p.lineTo(21, 17);
      case X5Glyph.back:
        p.moveTo(19, 12);
        p.lineTo(5, 12);
        p.moveTo(11, 6);
        p.lineTo(5, 12);
        p.lineTo(11, 18);
    }
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    if (glow) {
      canvas.drawPath(
        p,
        paint
          ..color = Colors.white.withAlpha(100)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        p,
        paint
          ..color = Colors.white.withAlpha(190)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
    canvas.drawPath(
      p,
      paint
        ..color = color
        ..maskFilter = null,
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.glyph != glyph || old.color != color || old.glow != glow;
}
