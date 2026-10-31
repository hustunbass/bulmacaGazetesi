import 'dart:math';

import 'package:flutter/material.dart';

/// Sayfa kıvrılmasının geometrisi (widget'tan bağımsız, birim testli).
///
/// Sayfanın [corner] noktası [target] noktasına çekilir. Katlama çizgisi bu iki
/// noktayı birleştiren doğrunun dik açıortayıdır. Köşe tarafındaki parça
/// katlama çizgisine göre yansıtılır: bu yansıma "kapak"tır (sayfanın arka
/// yüzü). Kalan parça (görünen sayfa) katlama çizgisinin diğer tarafıdır.
class CurlGeometry {
  CurlGeometry._(
    this.visible,
    this.cornerSide,
    this.flap,
    this.mid,
    this.normal,
  );

  /// Hâlâ yerinde duran sayfa parçası.
  final List<Offset> visible;

  /// Katlanan (köşe tarafındaki) orijinal parça; altta sonraki sayfa görünür.
  final List<Offset> cornerSide;

  /// Katlanan parçanın yansıması (sayfa sınırlarına kırpılmış).
  final List<Offset> flap;

  /// Katlama çizgisi üzerindeki nokta ve köşeye bakan birim normal.
  final Offset mid;
  final Offset normal;

  /// Köşe [target]'a yeterince yakınsa kıvrılma yoktur (null).
  static CurlGeometry? compute(Size size, Offset corner, Offset target) {
    final d = corner - target;
    if (d.distance < 0.5) return null;
    final n = d / d.distance;
    final m = (corner + target) / 2;
    final rect = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final visible = _clip(rect, n, n.dx * m.dx + n.dy * m.dy, keepBelow: true);
    final cside = _clip(rect, n, n.dx * m.dx + n.dy * m.dy, keepBelow: false);
    var flap = [
      for (final p in cside)
        p - n * (2 * ((p - m).dx * n.dx + (p - m).dy * n.dy)),
    ];
    // Kapağı sayfa dikdörtgenine kırp.
    flap = _clip(flap, const Offset(1, 0), 0, keepBelow: false);
    flap = _clip(flap, const Offset(-1, 0), -size.width, keepBelow: false);
    flap = _clip(flap, const Offset(0, 1), 0, keepBelow: false);
    flap = _clip(flap, const Offset(0, -1), -size.height, keepBelow: false);
    return CurlGeometry._(visible, cside, flap, m, n);
  }

  /// Sutherland–Hodgman: (p·n) <= d ([keepBelow]) ya da >= d tarafını tutar.
  static List<Offset> _clip(
    List<Offset> poly,
    Offset n,
    double d, {
    required bool keepBelow,
  }) {
    if (poly.isEmpty) return const [];
    double side(Offset p) {
      final v = p.dx * n.dx + p.dy * n.dy - d;
      return keepBelow ? -v : v; // >= 0 → içeride
    }

    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final sa = side(a), sb = side(b);
      if (sa >= 0) out.add(a);
      if ((sa >= 0) != (sb >= 0)) {
        final t = sa / (sa - sb);
        out.add(Offset.lerp(a, b, t)!);
      }
    }
    return out;
  }

  static double area(List<Offset> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s.abs() / 2;
  }

  static Path pathOf(List<Offset> poly) {
    final path = Path();
    if (poly.isEmpty) return path;
    path.moveTo(poly.first.dx, poly.first.dy);
    for (final p in poly.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// [t] (0 = düz, 1 = tamamen katlanmış) için köşe hedefi. Katlama çizgisi hafif
  /// eğik olsun diye hedef biraz yukarı kayar.
  static Offset targetFor(Size size, Offset corner, double t) {
    final x = corner.dx - t * size.width * 2.06;
    final y =
        corner.dy - sin(t * pi) * size.height * 0.10 - t * size.height * 0.04;
    return Offset(x, y);
  }
}

/// Kıvrılan sayfa: altta [under], yerinde kalan parça [front], üstte kapak.
class PageCurl extends StatelessWidget {
  const PageCurl({
    super.key,
    required this.front,
    required this.under,
    required this.t,
    required this.anchorY,
    required this.paper,
    required this.backPaper,
  });

  final Widget front;
  final Widget under;
  final double t;
  final double anchorY;
  final Color paper;
  final Color backPaper;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final corner = Offset(
          size.width,
          (anchorY * size.height).clamp(size.height * 0.3, size.height),
        );
        final g = t <= 0.001
            ? null
            : CurlGeometry.compute(
                size,
                corner,
                CurlGeometry.targetFor(size, corner, t),
              );
        if (g == null) return front;
        final fullyFolded = g.visible.length < 3;
        return Stack(
          fit: StackFit.expand,
          children: [
            under,
            // Kapağın altta bıraktığı gölge (sonraki sayfa üzerinde).
            IgnorePointer(
              child: CustomPaint(painter: _UnderShadow(g), size: size),
            ),
            if (!fullyFolded)
              ClipPath(clipper: _PolyClipper(g.visible), child: front),
            IgnorePointer(
              child: CustomPaint(painter: _Flap(g, backPaper), size: size),
            ),
          ],
        );
      },
    );
  }
}

class _PolyClipper extends CustomClipper<Path> {
  _PolyClipper(this.poly);
  final List<Offset> poly;
  @override
  Path getClip(Size size) => CurlGeometry.pathOf(poly);
  @override
  bool shouldReclip(_PolyClipper old) => true;
}

class _UnderShadow extends CustomPainter {
  _UnderShadow(this.g);
  final CurlGeometry g;

  @override
  void paint(Canvas canvas, Size size) {
    if (g.cornerSide.length < 3) return;
    // Katlama çizgisinden köşeye doğru solan gölge.
    canvas.save();
    canvas.clipPath(CurlGeometry.pathOf(g.cornerSide));
    canvas.drawPaint(
      Paint()..shader = _along(g.mid, g.normal * 46, [0.38, 0.0]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UnderShadow old) => old.g != g;
}

Shader _along(Offset from, Offset delta, List<double> alphas) {
  return LinearGradient(
    colors: [for (final a in alphas) Colors.black.withValues(alpha: a)],
  ).createShader(Rect.fromPoints(from, from + delta));
}

class _Flap extends CustomPainter {
  _Flap(this.g, this.paper);
  final CurlGeometry g;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    if (g.flap.length < 3) return;
    final path = CurlGeometry.pathOf(g.flap);
    // Kapağın yerinde kalan sayfaya düşen yumuşak gölgesi.
    canvas.save();
    canvas.clipPath(CurlGeometry.pathOf(g.visible));
    canvas.drawPath(
      path.shift(const Offset(-2, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.restore();
    // Kapağın kendisi: arka yüz kâğıdı.
    canvas.drawPath(path, Paint()..color = paper);
    // Silindir hissi: katlama çizgisinde koyu, içeri doğru açılan tonlama.
    canvas.save();
    canvas.clipPath(path);
    final inward = -g.normal;
    canvas.drawPaint(
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.0),
          ],
          stops: const [0, 0.35, 1],
        ).createShader(Rect.fromPoints(g.mid, g.mid + inward * 70)),
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.black.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(_Flap old) => old.g != g || old.paper != paper;
}
