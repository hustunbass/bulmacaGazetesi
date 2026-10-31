import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/sudoku_game.dart';
import '../theme.dart';

/// Türkçe Q klavye düzeni (Ğ, Ü, Ş, İ, Ö, Ç dahil). Büyük dokunma hedefleri.
class TurkishKeyboard extends StatelessWidget {
  const TurkishKeyboard({
    super.key,
    required this.onLetter,
    required this.onBackspace,
    this.haptics = true,
    this.keyHeight = 46,
    this.fontSize = 19,
  });

  final double keyHeight;
  final double fontSize;
  final void Function(String letter) onLetter;
  final VoidCallback onBackspace;
  final bool haptics;

  static const rows = ['QWERTYUIOPĞÜ', 'ASDFGHJKLŞİ', 'ZXCVBNMÖÇ'];

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Semantics(
      container: true,
      label: 'Türkçe harf klavyesi',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++)
              Row(
                children: [
                  for (final ch in rows[r].split(''))
                    _Key(
                      height: keyHeight,
                      fontSize: fontSize,
                      label: ch,
                      semantics: ch == 'I'
                          ? 'Noktasız I'
                          : (ch == 'İ' ? 'Noktalı İ' : ch),
                      onTap: () {
                        if (haptics) HapticFeedback.selectionClick();
                        onLetter(ch);
                      },
                    ),
                  if (r == rows.length - 1)
                    _Key(
                      height: keyHeight,
                      fontSize: fontSize,
                      icon: Icons.backspace_outlined,
                      semantics: 'Geri sil',
                      flex: 2,
                      fill: pal.paperDeep,
                      onTap: () {
                        if (haptics) HapticFeedback.selectionClick();
                        onBackspace();
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    required this.semantics,
    required this.onTap,
    this.flex = 1,
    this.fill,
    this.height = 46,
    this.fontSize = 19,
  });
  final double height;
  final double fontSize;
  final String? label;
  final IconData? icon;
  final String semantics;
  final VoidCallback onTap;
  final int flex;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          button: true,
          label: semantics,
          excludeSemantics: true,
          onTap: onTap,
          child: Material(
            color: fill ?? pal.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: pal.rule),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onTap,
              child: SizedBox(
                height: height,
                child: Center(
                  child: icon != null
                      ? Icon(icon, size: fontSize + 3, color: pal.ink)
                      : Text(
                          label!,
                          style: sansStyle(
                            pal.ink,
                            fontSize,
                            w: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sudoku sayı takımı. Dokuz doğru yerleşimi tamamlanan rakam işaretlenir
/// (renk + onay simgesi).
class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.game,
    required this.onDigit,
    this.haptics = true,
    this.keyHeight = 54,
    this.fontSize = 24,
  });
  final double keyHeight;
  final double fontSize;
  final SudokuGame game;
  final void Function(int d) onDigit;
  final bool haptics;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
      child: Row(
        children: [
          for (var d = 1; d <= 9; d++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: game.digitDone(d)
                      ? 'Rakam $d, dokuz yerleşim tamamlandı'
                      : 'Rakam $d, ${9 - game.placedCorrect(d)} yer kaldı',
                  onTap: () => onDigit(d),
                  child: Material(
                    color: game.digitDone(d) ? pal.paperDeep : pal.paper,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(color: pal.rule),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        if (haptics) HapticFeedback.selectionClick();
                        onDigit(d);
                      },
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: keyHeight),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$d',
                              style: serifStyle(
                                game.digitDone(d) ? pal.inkSoft : pal.ink,
                                fontSize,
                              ),
                            ),
                            Icon(
                              game.digitDone(d) ? Icons.check : Icons.remove,
                              size: 12,
                              color: game.digitDone(d) ? pal.ok : pal.rule,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
