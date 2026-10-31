import 'dart:math';

import 'package:bulmaca_postasi/ui/widgets/page_curl.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(400, 800);
  final corner = Offset(size.width, size.height * 0.9);

  test('t=0: kıvrılma yok', () {
    expect(CurlGeometry.compute(size, corner, corner), isNull);
  });

  test('görünen parça + katlanan parça = tüm sayfa alanı', () {
    for (final t in [0.05, 0.2, 0.4, 0.6, 0.8, 0.95]) {
      final g = CurlGeometry.compute(
        size,
        corner,
        CurlGeometry.targetFor(size, corner, t),
      )!;
      final sum =
          CurlGeometry.area(g.visible) + CurlGeometry.area(g.cornerSide);
      expect(sum, closeTo(size.width * size.height, 1), reason: 't=$t');
    }
  });

  test(
    'kapak, katlanan parçanın yansımasıdır (alan korunur, sayfa içinde kalır)',
    () {
      final g = CurlGeometry.compute(
        size,
        corner,
        CurlGeometry.targetFor(size, corner, 0.25),
      )!;
      expect(
        CurlGeometry.area(g.flap),
        closeTo(CurlGeometry.area(g.cornerSide), 1),
      );
      for (final p in g.flap) {
        expect(p.dx, inInclusiveRange(-0.01, size.width + 0.01));
        expect(p.dy, inInclusiveRange(-0.01, size.height + 0.01));
      }
    },
  );

  test('köşe, hedef noktaya yansır (katlama çizgisi dik açıortay)', () {
    final target = CurlGeometry.targetFor(size, corner, 0.3);
    final g = CurlGeometry.compute(size, corner, target)!;
    final dc =
        (corner - g.mid).dx * g.normal.dx + (corner - g.mid).dy * g.normal.dy;
    final dt =
        (target - g.mid).dx * g.normal.dx + (target - g.mid).dy * g.normal.dy;
    expect(dc, closeTo(-dt, 1e-6));
    expect(g.normal.distance, closeTo(1, 1e-9));
  });

  test('t=1: sayfa tamamen katlanmış, görünen alan ~0', () {
    final g = CurlGeometry.compute(
      size,
      corner,
      CurlGeometry.targetFor(size, corner, 1),
    )!;
    expect(
      CurlGeometry.area(g.visible),
      lessThan(size.width * size.height * 0.03),
    );
  });

  test('ilerledikçe görünen alan tekdüze azalır', () {
    var prev = double.infinity;
    for (var i = 1; i <= 20; i++) {
      final t = i / 20;
      final g = CurlGeometry.compute(
        size,
        corner,
        CurlGeometry.targetFor(size, corner, t),
      )!;
      final a = CurlGeometry.area(g.visible);
      expect(a, lessThanOrEqualTo(prev + 0.5), reason: 't=$t');
      prev = a;
    }
    expect(prev, isNot(isNaN));
    expect(sqrt(prev), isNonNegative);
  });
}
