import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Kâğıt dokusu: tek bir küçük karo bir kez üretilir, önbelleğe alınır ve
/// döşenerek çizilir. Her karede yeniden üretilmez. Doku çok hafiftir ve
/// okunabilirliği azaltmaz; metin üzerinde leke/kir efekti yoktur.
class PaperTexture {
  PaperTexture._();

  /// Testlerde ve düşük donanımda kapatılabilir.
  static bool enabled = true;

  static Future<MemoryImage?>? _tile;

  static Future<MemoryImage?> tile() => _tile ??= _make();

  static Future<MemoryImage?> _make() async {
    try {
      const size = 192;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      final rnd = Random(42);
      final p = Paint();
      for (var i = 0; i < 2600; i++) {
        final x = rnd.nextDouble() * size;
        final y = rnd.nextDouble() * size;
        final a = (rnd.nextDouble() * 10 + 2).toInt();
        p.color = Color.fromARGB(a, 70, 55, 30);
        canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), p);
      }
      // Çok ince lif çizgileri.
      for (var i = 0; i < 90; i++) {
        final x = rnd.nextDouble() * size;
        final y = rnd.nextDouble() * size;
        p
          ..color = const Color(0x0A3C2D14)
          ..strokeWidth = 0.6;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + rnd.nextDouble() * 6 - 3, y + rnd.nextDouble() * 6 - 3),
          p,
        );
      }
      final img = await rec.endRecording().toImage(size, size);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return MemoryImage(Uint8List.view(data.buffer));
    } on Object {
      return null;
    }
  }
}

/// Kâğıt zemini + ince sayfa gölgesi.
class PaperSheet extends StatelessWidget {
  const PaperSheet({super.key, required this.child, this.shadow = true});
  final Widget child;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final dark = pal.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pal.paper,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: PaperTextureOverlay(child: child),
    );
  }
}

class PaperTextureOverlay extends StatelessWidget {
  const PaperTextureOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PaperTexture.enabled || context.pal.brightness == Brightness.dark) {
      return child;
    }
    return FutureBuilder<MemoryImage?>(
      future: PaperTexture.tile(),
      builder: (context, snap) {
        final img = snap.data;
        if (img == null) return child;
        return DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(image: img, repeat: ImageRepeat.repeat),
          ),
          child: child,
        );
      },
    );
  }
}

/// İnce gazete ayırıcısı (çift çizgi).
class NewsRule extends StatelessWidget {
  const NewsRule({super.key, this.vertical = false, this.heavy = false});
  final bool vertical;
  final bool heavy;

  @override
  Widget build(BuildContext context) {
    final c = context.pal.ink;
    final line = Container(
      width: vertical ? 1 : null,
      height: vertical ? null : (heavy ? 2 : 1),
      color: c.withValues(alpha: heavy ? 0.9 : 0.55),
    );
    final gap = SizedBox(width: vertical ? 2 : 0, height: vertical ? 0 : 2);
    final thin = Container(
      width: vertical ? 0.5 : null,
      height: vertical ? null : 0.5,
      color: c.withValues(alpha: 0.5),
    );
    return vertical
        ? Row(mainAxisSize: MainAxisSize.min, children: [line, gap, thin])
        : Column(mainAxisSize: MainAxisSize.min, children: [line, gap, thin]);
  }
}
