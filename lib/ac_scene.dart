import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'ui_style.dart';

class AcScene extends StatefulWidget {
  final bool power, oscillating, light, active;
  final int? temperature;
  final String fan;
  final VoidCallback? toggleDisplay;
  const AcScene({
    super.key,
    required this.power,
    required this.oscillating,
    required this.light,
    required this.temperature,
    required this.fan,
    required this.toggleDisplay,
    this.active = true,
  });

  @override
  State<AcScene> createState() => _AcSceneState();
}

class _AcSceneState extends State<AcScene> with TickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );
  bool _reduce = false;

  void _animate() {
    if (_reduce || !widget.active || !TickerMode.of(context)) {
      _open.stop();
      _flow.stop();
      _open.value = widget.power ? 1 : 0;
    } else {
      if (widget.power) {
        _open.forward();
        if (!_flow.isAnimating) _flow.repeat();
      } else {
        _open.reverse();
        _flow.stop();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _animate();
  }

  @override
  void didUpdateWidget(AcScene old) {
    super.didUpdateWidget(old);
    if (old.power != widget.power || old.active != widget.active) _animate();
  }

  @override
  void dispose() {
    _open.dispose();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      height: 146,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(340.0, constraints.maxWidth);
          return Center(
            child: SizedBox(
              width: width,
              height: 146,
              child: AnimatedBuilder(
                animation: Listenable.merge([_open, _flow]),
                builder: (context, _) {
                  final elapsed =
                      (_flow.lastElapsedDuration?.inMicroseconds ?? 0) / 1000;
                  final sweep =
                      widget.power && widget.oscillating && !_reduce
                          ? math.sin(
                            math.max(0, elapsed - 1100) * math.pi * 2 / 4200,
                          )
                          : 0.0;
                  final opening = Curves.easeOutCubic.transform(_open.value);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 21,
                        width: width,
                        height: 132,
                        child: AnimatedOpacity(
                          opacity: widget.power ? 1 : 0,
                          duration: Duration(milliseconds: _reduce ? 0 : 400),
                          child: CustomPaint(
                            painter: _WindPainter(elapsed, sweep, widget.fan),
                          ),
                        ),
                      ),
                      Positioned(
                        left: width / 2 - 73,
                        top: 30,
                        width: 146,
                        height: 49,
                        child: Transform.rotate(
                          angle: 5 * math.pi / 180,
                          filterQuality: FilterQuality.high,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipPath(
                                clipper: _BodyClip(),
                                clipBehavior: Clip.antiAliasWithSaveLayer,
                                child: ColorFiltered(
                                  colorFilter: const ColorFilter.matrix([
                                    .3808,
                                    .3626,
                                    .0366,
                                    0,
                                    0,
                                    .1078,
                                    .6356,
                                    .0366,
                                    0,
                                    0,
                                    .1078,
                                    .3626,
                                    .3096,
                                    0,
                                    0,
                                    0,
                                    0,
                                    0,
                                    1,
                                    0,
                                  ]),
                                  child: Image.asset(
                                    'assets/mini-split.png',
                                    width: 146,
                                    height: 49,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.high,
                                    isAntiAlias: true,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 9.5,
                                top: 34.6,
                                width: 125.6,
                                height: 9.3,
                                child: Transform(
                                  alignment: Alignment.bottomCenter,
                                  transform: Matrix4.diagonal3Values(
                                    1,
                                    (1 - opening * .42) * (1 - sweep * .25),
                                    1,
                                  ),
                                  filterQuality: FilterQuality.high,
                                  child: CustomPaint(painter: _FlapPainter()),
                                ),
                              ),
                              Positioned(
                                right: 10.2,
                                top: -3,
                                width: 44,
                                height: 44,
                                child: Semantics(
                                  button: true,
                                  label:
                                      widget.light
                                          ? 'Apagar display del minisplit'
                                          : 'Encender display del minisplit',
                                  enabled: widget.toggleDisplay != null,
                                  child: TextButton(
                                    key: const ValueKey('display-button'),
                                    onPressed: widget.toggleDisplay,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(44, 44),
                                      backgroundColor: Colors.transparent,
                                    ),
                                    child: Text(
                                      widget.temperature?.toString() ?? '—',
                                      style: TextStyle(
                                        fontFamily: 'RobotoCondensed',
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        height: 1,
                                        letterSpacing: .5,
                                        color:
                                            widget.power && widget.light
                                                ? const Color(0xfff5fff9)
                                                : const Color(0xff506157),
                                        shadows:
                                            widget.power && widget.light
                                                ? X5Style.bloom
                                                : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _BodyClip extends CustomClipper<Path> {
  @override
  Path getClip(Size size) =>
      Path()
        ..moveTo(size.width * .10, size.height * .065)
        ..lineTo(size.width * .95, size.height * .065)
        ..quadraticBezierTo(
          size.width * .985,
          size.height * .065,
          size.width * .985,
          size.height * .18,
        )
        ..lineTo(size.width * .985, size.height * .79)
        ..quadraticBezierTo(
          size.width * .985,
          size.height * .905,
          size.width * .94,
          size.height * .905,
        )
        ..lineTo(size.width * .10, size.height * .905)
        ..quadraticBezierTo(
          size.width * .018,
          size.height * .905,
          size.width * .018,
          size.height * .71,
        )
        ..lineTo(size.width * .018, size.height * .24)
        ..quadraticBezierTo(
          size.width * .018,
          size.height * .065,
          size.width * .10,
          size.height * .065,
        )
        ..close();
  @override
  bool shouldReclip(_BodyClip old) => false;
}

class _FlapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1.7)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xffc2c3bf), Color(0xffb2b5af), Color(0xff899188)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * .7, size.width, size.height * .3),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xff727c72),
    );
    canvas.drawLine(
      const Offset(2, 1),
      Offset(size.width - 2, 1),
      Paint()
        ..color = Colors.white.withAlpha(130)
        ..strokeWidth = .45,
    );
  }

  @override
  bool shouldRepaint(_FlapPainter old) => false;
}

class _WindPainter extends CustomPainter {
  final double time, sweep;
  final String fan;
  const _WindPainter(this.time, this.sweep, this.fan);
  @override
  void paint(Canvas canvas, Size size) {
    final speed =
        {
          'auto': .00045,
          'low': .0003,
          'middle': .00045,
          'high': .00065,
          'strong': .00085,
          'mute': .00022,
        }[fan] ??
        .00045;
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < 32; i++) {
      final u = i / 31;
      final x = size.width / 2 - 62 + u * 124;
      final y = 47 + u * 11;
      final spread = (u - .5) * (53 + sweep * 14);
      final length = 64 + sweep * 14;
      final progress = (time * speed + i * .173) % 1;
      paint
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00d8e6db),
            Color(0x1fe0eee5),
            Color(0x12e0eee5),
            Color(0x00d8e6db),
          ],
          stops: const [0, .15, .55, 1],
        ).createShader(Rect.fromLTWH(x - 1, y, 2, length));
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..cubicTo(
            x,
            y + 17,
            x + spread * .7,
            y + length * .75,
            x + spread,
            y + length,
          ),
        paint,
      );
      final trail = Path();
      for (var j = 0; j <= 8; j++) {
        final t = math.max(0.0, progress - .17 + j * .021);
        final tx =
            x +
            spread * math.sin(t * math.pi / 2) +
            math.sin(t * 7 + i) * 1.7 * t;
        final ty = y + length * t;
        if (j == 0) {
          trail.moveTo(tx, ty);
        } else {
          trail.lineTo(tx, ty);
        }
      }
      paint
        ..shader = null
        ..color = const Color(
          0xffe0eee5,
        ).withAlpha((math.sin(progress * math.pi) * .46 * 255).round())
        ..strokeWidth = 1.5 + math.sin(i * 2) * .4;
      canvas.drawPath(trail, paint);
    }
  }

  @override
  bool shouldRepaint(_WindPainter old) =>
      old.time != time || old.sweep != sweep || old.fan != fan;
}
