import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../domain/sudoku_game.dart';
import '../../domain/sudoku_solver.dart';
import '../../state/attempt_session.dart';
import '../theme.dart';

/// Sudoku ızgarası. Statik katman çizgileri ve başlangıç sayılarını, dinamik
/// katman vurguları, girişleri ve notları çizer.
class SudokuGridView extends StatelessWidget {
  const SudokuGridView({
    super.key,
    required this.session,
    required this.onCellTap,
    this.showConflicts = true,
    this.showWrong = true,
  });

  final AttemptSession session;
  final void Function(int cell) onCellTap;
  final bool showConflicts;

  /// Kontrol sonrası cevap anahtarına göre yanlış rakamları işaretle.
  final bool showWrong;

  @override
  Widget build(BuildContext context) {
    final game = session.sudoku!;
    final pal = context.pal;
    return LayoutBuilder(
      builder: (context, box) {
        var side = box.maxWidth;
        if (box.hasBoundedHeight) side = min(side, box.maxHeight);
        final cell = side / 9;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final c = (d.localPosition.dx / cell).floor().clamp(0, 8);
                final r = (d.localPosition.dy / cell).floor().clamp(0, 8);
                onCellTap(r * 9 + c);
              },
              child: Stack(
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size(side, side),
                      painter: _StaticSudoku(game, pal, cell),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size(side, side),
                      painter: _DynamicSudoku(
                        session,
                        game,
                        pal,
                        cell,
                        showConflicts,
                        showWrong,
                        onCellTap,
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

class _StaticSudoku extends CustomPainter {
  _StaticSudoku(this.game, this.pal, this.cell);
  final SudokuGame game;
  final Palette pal;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = pal.paper);
    for (var i = 0; i <= 9; i++) {
      final thick = i % 3 == 0;
      final p = Paint()
        ..color = pal.ink.withValues(alpha: thick ? 0.95 : 0.35)
        ..strokeWidth = thick ? 2.2 : 0.7;
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), p);
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), p);
    }
    for (var i = 0; i < 81; i++) {
      if (!game.isGiven(i)) continue;
      _digit(
        canvas,
        i,
        game.given[i],
        pal.ink,
        FontWeight.w800,
        cell,
        serif: true,
      );
    }
  }

  @override
  bool shouldRepaint(_StaticSudoku old) =>
      old.cell != cell || old.pal != pal || old.game != game;
}

void _digit(
  Canvas canvas,
  int i,
  int d,
  Color color,
  FontWeight w,
  double cell, {
  bool serif = false,
}) {
  final r = i ~/ 9, c = i % 9;
  final style = serif
      ? serifStyle(color, cell * 0.6, w: w, h: 1.0)
      : sansStyle(color, cell * 0.6, w: w, h: 1.0);
  final tp = TextPainter(
    text: TextSpan(text: '$d', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(
    canvas,
    Offset(c * cell + (cell - tp.width) / 2, r * cell + (cell - tp.height) / 2),
  );
}

class _DynamicSudoku extends CustomPainter {
  _DynamicSudoku(
    this.session,
    this.game,
    this.pal,
    this.cell,
    this.showConflicts,
    this.showWrong,
    this.onTap,
  ) : super(repaint: session);
  final AttemptSession session;
  final SudokuGame game;
  final Palette pal;
  final double cell;
  final bool showConflicts;
  final bool showWrong;
  final void Function(int) onTap;

  @override
  void paint(Canvas canvas, Size size) {
    final sel = game.selCell;
    final selDigit = sel >= 0 ? game.values[sel] : 0;
    final conflicts = showConflicts ? game.conflicts : const <int>{};
    final selRow = sel < 0 ? -1 : sel ~/ 9;
    final selCol = sel < 0 ? -1 : sel % 9;
    final selBox = sel < 0 ? -1 : (sel ~/ 27) * 3 + (sel % 9) ~/ 3;
    for (var i = 0; i < 81; i++) {
      final r = i ~/ 9, c = i % 9;
      final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
      Color? fill;
      if (sel >= 0 &&
          (r == selRow || c == selCol || (r ~/ 3) * 3 + c ~/ 3 == selBox)) {
        fill = pal.related.withValues(alpha: 0.55);
      }
      if (game.hinted.contains(i)) fill = pal.hintFill;
      if (selDigit != 0 && game.values[i] == selDigit && i != sel) {
        fill = pal.selection.withValues(alpha: 0.6);
      }
      if (i == sel) fill = pal.selection;
      if (fill != null) {
        canvas.drawRect(rect.deflate(1), Paint()..color = fill);
      }
      final v = game.values[i];
      if (v != 0 && !game.isGiven(i)) {
        final bad =
            conflicts.contains(i) || (showWrong && game.wrong.contains(i));
        _digit(canvas, i, v, bad ? pal.bad : pal.accent, FontWeight.w600, cell);
        if (bad) {
          // Hata: renk + altı çizgili çapraz işaret (renkten bağımsız).
          canvas.drawLine(
            rect.bottomLeft + const Offset(3, -3),
            rect.topRight + const Offset(-3, 3),
            Paint()
              ..color = pal.bad
              ..strokeWidth = 1.4,
          );
        }
      } else if (v != 0 && game.isGiven(i) && conflicts.contains(i)) {
        canvas.drawRect(
          rect.deflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = pal.bad,
        );
      }
      if (v == 0 && game.notes[i] != 0) {
        for (var d = 1; d <= 9; d++) {
          if (game.notes[i] & SudokuSolver.bit(d) == 0) continue;
          final tp = TextPainter(
            text: TextSpan(
              text: '$d',
              style: sansStyle(
                pal.inkSoft,
                cell * 0.24,
                w: FontWeight.w600,
                h: 1.0,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final nr = (d - 1) ~/ 3, nc = (d - 1) % 3;
          tp.paint(
            canvas,
            Offset(
              rect.left + cell / 3 * nc + (cell / 3 - tp.width) / 2,
              rect.top + cell / 3 * nr + (cell / 3 - tp.height) / 2,
            ),
          );
        }
      }
      if (game.hinted.contains(i)) {
        final t = cell * 0.2;
        canvas.drawPath(
          Path()
            ..moveTo(rect.right - t, rect.top + 1)
            ..lineTo(rect.right - 1, rect.top + 1)
            ..lineTo(rect.right - 1, rect.top + t)
            ..close(),
          Paint()..color = pal.ok,
        );
      }
      if (i == sel) {
        canvas.drawRect(
          rect.deflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = pal.accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DynamicSudoku old) =>
      old.cell != cell ||
      old.pal != pal ||
      old.showConflicts != showConflicts ||
      old.showWrong != showWrong ||
      old.game != game;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
    return [
      for (var i = 0; i < 81; i++)
        CustomPainterSemantics(
          rect: Rect.fromLTWH((i % 9) * cell, (i ~/ 9) * cell, cell, cell),
          properties: SemanticsProperties(
            textDirection: TextDirection.ltr,
            label:
                'Satır ${i ~/ 9 + 1}, sütun ${i % 9 + 1}, '
                '${game.values[i] == 0 ? (game.notes[i] != 0 ? 'boş, notlu' : 'boş') : 'sayı ${game.values[i]}'}, '
                '${game.isGiven(i)
                    ? 'başlangıç sayısı, değiştirilemez'
                    : game.hinted.contains(i)
                    ? 'ipucuyla açıldı, kilitli'
                    : 'düzenlenebilir'}',
            button: true,
            selected: i == game.selCell,
            onTap: () => onTap(i),
          ),
        ),
    ];
  };
}
