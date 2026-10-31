import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../domain/puzzle.dart';
import '../../domain/word_game.dart';
import '../../domain/word_structure.dart';
import '../../state/attempt_session.dart';
import '../theme.dart';

/// Çengel, kare ve klasik bulmacalar için ızgara.
///
/// İki ayrı çizim sınırı vardır: statik katman (bloklar, numaralar, soru
/// hücreleri, oklar) yalnızca boyut/palet değişince çizilir; dinamik katman
/// (seçim vurgusu, harfler, hata işaretleri) oturumu dinler. Hücre değişimi
/// tüm gazeteyi yeniden çizmez.
class WordGridView extends StatelessWidget {
  const WordGridView({
    super.key,
    required this.session,
    required this.onCellTap,
    this.onClueTap,
    this.showWrong = true,
    this.live = true,
    this.maxCell,
  });

  final AttemptSession session;
  final void Function(int cell) onCellTap;
  final void Function(int cell)? onClueTap;
  final bool showWrong;

  /// Anında geri bildirim: yanlış harf kırmızı, doğru kelime yeşil.
  final bool live;
  final double? maxCell;

  @override
  Widget build(BuildContext context) {
    final game = session.word!;
    final s = game.structure;
    final pal = context.pal;
    return LayoutBuilder(
      builder: (context, box) {
        var cell = box.maxWidth / s.cols;
        if (box.hasBoundedHeight) cell = min(cell, box.maxHeight / s.rows);
        if (maxCell != null) cell = min(cell, maxCell!);
        final size = Size(cell * s.cols, cell * s.rows);
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final c = (d.localPosition.dx / cell).floor();
                final r = (d.localPosition.dy / cell).floor();
                if (r < 0 || c < 0 || r >= s.rows || c >= s.cols) return;
                final i = s.idx(r, c);
                if (s.isPlayable(i)) {
                  onCellTap(i);
                } else if (s.clueCells.containsKey(i)) {
                  onClueTap?.call(i);
                }
              },
              child: Stack(
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: _StaticPainter(s, pal, cell),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: _DynamicPainter(
                        session,
                        game,
                        pal,
                        cell,
                        showWrong,
                        live,
                        onCellTap,
                        onClueTap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StaticPainter extends CustomPainter {
  _StaticPainter(this.s, this.pal, this.cell);
  final WordStructure s;
  final Palette pal;
  final double cell;

  bool get _cengel => s.def.type == PuzzleType.cengel;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = pal.ink.withValues(alpha: 0.75)
      ..strokeWidth = 0.8;
    final nums = _cengel
        ? const <int, int>{}
        : WordStructure.numbering(
            s.rows,
            s.cols,
            (r, c) =>
                r >= 0 &&
                c >= 0 &&
                r < s.rows &&
                c < s.cols &&
                s.isPlayable(s.idx(r, c)),
          );
    for (var r = 0; r < s.rows; r++) {
      for (var c = 0; c < s.cols; c++) {
        final i = s.idx(r, c);
        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        if (s.isPlayable(i)) {
          canvas.drawRect(rect, Paint()..color = pal.paper);
        } else if (_cengel) {
          final isClue = s.clueCells.containsKey(i);
          canvas.drawRect(
            rect,
            Paint()
              ..color = isClue
                  ? pal.paperDeep
                  : pal.rule.withValues(alpha: 0.45),
          );
          if (isClue) _paintClueCell(canvas, rect, s.clueCells[i]!);
        } else {
          canvas.drawRect(rect, Paint()..color = pal.block);
        }
        final n = nums[i];
        if (n != null) {
          final tp = TextPainter(
            text: TextSpan(
              text: '$n',
              style: sansStyle(
                pal.inkSoft,
                max(7, cell * 0.26),
                w: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(rect.left + 1.5, rect.top + 0.5));
        }
      }
    }
    for (var r = 0; r <= s.rows; r++) {
      canvas.drawLine(Offset(0, r * cell), Offset(size.width, r * cell), line);
    }
    for (var c = 0; c <= s.cols; c++) {
      canvas.drawLine(Offset(c * cell, 0), Offset(c * cell, size.height), line);
    }
  }

  void _paintClueCell(Canvas canvas, Rect rect, List<int> entries) {
    final inner = rect.deflate(1.5);
    final parts = entries.length;
    final h = inner.height / parts;
    for (var k = 0; k < parts; k++) {
      final e = s.entries[entries[k]];
      final area = Rect.fromLTWH(inner.left, inner.top + h * k, inner.width, h);
      // Ok için yer bırak.
      final textArea = e.dir == Dir.across
          ? Rect.fromLTRB(
              area.left,
              area.top,
              area.right - cell * 0.16,
              area.bottom,
            )
          : Rect.fromLTRB(
              area.left,
              area.top,
              area.right,
              area.bottom - cell * 0.16,
            );
      final fs = max(5.0, cell * (parts == 1 ? 0.19 : 0.15));
      final tp = TextPainter(
        text: TextSpan(
          text: e.clue,
          style: sansStyle(pal.ink, fs, w: FontWeight.w600, h: 1.0),
        ),
        textDirection: TextDirection.ltr,
        maxLines: max(1, (textArea.height / (fs * 1.05)).floor()),
        ellipsis: '…',
        textAlign: TextAlign.center,
      )..layout(maxWidth: textArea.width);
      tp.paint(
        canvas,
        Offset(
          textArea.left + (textArea.width - tp.width) / 2,
          textArea.top + max(0, (textArea.height - tp.height) / 2),
        ),
      );
      _arrow(canvas, area, e.dir);
      if (parts == 2 && k == 0) {
        canvas.drawLine(
          Offset(inner.left, area.bottom),
          Offset(inner.right, area.bottom),
          Paint()
            ..color = pal.rule
            ..strokeWidth = 0.6,
        );
      }
    }
  }

  /// Ok, cevabın yazılacağı yönü gösterir: yatayda sağ kenarda, dikeyde alt
  /// kenarda.
  void _arrow(Canvas canvas, Rect area, Dir dir) {
    final a = max(3.0, cell * 0.12);
    final p = Path();
    if (dir == Dir.across) {
      final cx = area.right - 0.5, cy = area.center.dy;
      p
        ..moveTo(cx - a, cy - a)
        ..lineTo(cx, cy)
        ..lineTo(cx - a, cy + a)
        ..close();
    } else {
      final cx = area.center.dx, cy = area.bottom - 0.5;
      p
        ..moveTo(cx - a, cy - a)
        ..lineTo(cx, cy)
        ..lineTo(cx + a, cy - a)
        ..close();
    }
    canvas.drawPath(p, Paint()..color = pal.accent);
  }

  @override
  bool shouldRepaint(_StaticPainter old) =>
      old.cell != cell || old.pal != pal || old.s != s;
}

class _DynamicPainter extends CustomPainter {
  _DynamicPainter(
    this.session,
    this.game,
    this.pal,
    this.cell,
    this.showWrong,
    this.live,
    this.onCellTap,
    this.onClueTap,
  ) : super(repaint: session);

  final AttemptSession session;
  final WordGame game;
  final Palette pal;
  final double cell;
  final bool showWrong;
  final bool live;
  final void Function(int) onCellTap;
  final void Function(int)? onClueTap;

  WordStructure get s => game.structure;

  @override
  void paint(Canvas canvas, Size size) {
    final active = game.activeCells.toSet();
    // Tamamen doğru yazılmış kelimeler: tüm hücreleri yeşil, ilk hücrede onay.
    final doneCells = <int>{};
    final doneStarts = <int>{};
    if (live) {
      for (final k in game.correctEntries()) {
        final cells = s.entryCells(k);
        doneCells.addAll(cells);
        doneStarts.add(cells.first);
      }
    }
    final green = Color.alphaBlend(pal.ok.withValues(alpha: 0.32), pal.paper);
    for (var i = 0; i < game.letters.length; i++) {
      if (!s.isPlayable(i)) continue;
      final r = i ~/ s.cols, c = i % s.cols;
      final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
      Color? fill;
      if (game.hinted[i]) fill = pal.hintFill;
      if (active.contains(i)) fill = pal.related;
      if (doneCells.contains(i)) fill = green;
      if (i == game.selCell) fill = pal.selection;
      if (fill != null) {
        canvas.drawRect(rect.deflate(0.5), Paint()..color = fill);
      }
      if (game.hinted[i]) {
        // Renk dışında da ayırt edilsin: köşede küçük üçgen.
        final t = cell * 0.22;
        canvas.drawPath(
          Path()
            ..moveTo(rect.right - t, rect.top + 0.5)
            ..lineTo(rect.right - 0.5, rect.top + 0.5)
            ..lineTo(rect.right - 0.5, rect.top + t)
            ..close(),
          Paint()..color = pal.ok,
        );
      }
      final liveWrong = live && game.isLetterWrong(i);
      final checkedWrong = showWrong && game.wrong.contains(i);
      final isWrong = liveWrong || checkedWrong;
      final letter = game.letters[i];
      if (letter.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: letter,
            style: sansStyle(
              isWrong ? pal.bad : pal.ink,
              cell * 0.58,
              w: FontWeight.w700,
              h: 1.0,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            rect.left + (cell - tp.width) / 2,
            rect.top + (cell - tp.height) / 2 + cell * 0.03,
          ),
        );
      }
      if (liveWrong) {
        // Anında geri bildirim: kırmızı harf + kalın kırmızı alt çizgi.
        canvas.drawLine(
          rect.bottomLeft + Offset(cell * 0.12, -cell * 0.1),
          rect.bottomRight + Offset(-cell * 0.12, -cell * 0.1),
          Paint()
            ..color = pal.bad
            ..strokeWidth = max(2.0, cell * 0.09)
            ..strokeCap = StrokeCap.round,
        );
      }
      if (doneStarts.contains(i)) {
        final ck = TextPainter(
          text: TextSpan(
            text: '✓',
            style: sansStyle(pal.ok, cell * 0.3, w: FontWeight.w900, h: 1.0),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        ck.paint(
          canvas,
          Offset(rect.right - ck.width - 2, rect.bottom - ck.height - 1),
        );
      }
      if (checkedWrong && !liveWrong) {
        // Elle kontrol: renk + çapraz çizgi.
        canvas.drawLine(
          rect.bottomLeft + Offset(2, -2),
          rect.topRight + Offset(-2, 2),
          Paint()
            ..color = pal.bad
            ..strokeWidth = 1.4,
        );
      }
      if (i == game.selCell) {
        canvas.drawRect(
          rect.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = pal.accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DynamicPainter old) =>
      old.cell != cell ||
      old.pal != pal ||
      old.showWrong != showWrong ||
      old.live != live ||
      old.game != game;

  /// Ekran okuyucu: konum, mevcut değer, düzenlenebilirlik ve ilgili soru.
  /// Çözüm harfleri açıklanmaz.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
    final out = <CustomPainterSemantics>[];
    for (var i = 0; i < game.letters.length; i++) {
      final r = i ~/ s.cols, c = i % s.cols;
      final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
      if (s.isPlayable(i)) {
        final ks = s.cellEntries[i] ?? const <int>[];
        final clues = [
          for (final k in ks)
            '${s.entries[k].dir.label}: ${s.entries[k].clue}, ${s.entries[k].length} harf',
        ].join('; ');
        final value = game.letters[i].isEmpty
            ? 'boş'
            : 'harf ${game.letters[i]}';
        final status = !live
            ? ''
            : game.isLetterWrong(i)
            ? ', yanlış harf'
            : ks.any(game.isEntryCorrect)
            ? ', kelime doğru'
            : '';
        final locked = game.hinted[i]
            ? 'ipucuyla açıldı, kilitli'
            : 'düzenlenebilir';
        out.add(
          CustomPainterSemantics(
            rect: rect,
            properties: SemanticsProperties(
              textDirection: TextDirection.ltr,
              label:
                  'Satır ${r + 1}, sütun ${c + 1}, $value$status, $locked. $clues',
              button: true,
              selected: i == game.selCell,
              onTap: () => onCellTap(i),
            ),
          ),
        );
      } else if (s.clueCells.containsKey(i)) {
        final clues = [
          for (final k in s.clueCells[i]!)
            '${s.entries[k].dir.label}: ${s.entries[k].clue}',
        ].join('; ');
        out.add(
          CustomPainterSemantics(
            rect: rect,
            properties: SemanticsProperties(
              textDirection: TextDirection.ltr,
              label: 'Soru hücresi. $clues',
              button: true,
              onTap: () => onClueTap?.call(i),
            ),
          ),
        );
      }
    }
    return out;
  };
}
