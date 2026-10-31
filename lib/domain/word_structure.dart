import 'puzzle.dart';

/// Kelime bulmacasından türetilen, değişmeyen yapı bilgisi.
/// Oyun durumundan bağımsızdır; arayüz ve motor tarafından paylaşılır.
class WordStructure {
  WordStructure._(this.def, this.playable, this.cellEntries, this.clueCells);

  final PuzzleDefinition def;

  /// Harf yazılabilen hücreler (indeks = satır * sütun + sütun).
  final List<bool> playable;

  /// Hücre indeksi → o hücreden geçen giriş indeksleri (en çok iki).
  final Map<int, List<int>> cellEntries;

  /// Çengel: soru hücresi indeksi → bu hücredeki giriş indeksleri.
  final Map<int, List<int>> clueCells;

  int get rows => def.rows;
  int get cols => def.cols;
  List<WordEntry> get entries => def.entries;

  int idx(int r, int c) => r * def.cols + c;
  bool isPlayable(int i) => i >= 0 && i < playable.length && playable[i];

  factory WordStructure.build(PuzzleDefinition def) {
    final playable = <bool>[
      for (final row in def.grid)
        for (var c = 0; c < def.cols; c++) c < row.length && row[c] != '#',
    ];
    final cellEntries = <int, List<int>>{};
    final clueCells = <int, List<int>>{};
    for (var k = 0; k < def.entries.length; k++) {
      final e = def.entries[k];
      for (final (r, c) in e.cells) {
        cellEntries.putIfAbsent(r * def.cols + c, () => []).add(k);
      }
      if (e.hasClueCell) {
        clueCells
            .putIfAbsent(e.clueRow * def.cols + e.clueCol, () => [])
            .add(k);
      }
    }
    return WordStructure._(def, playable, cellEntries, clueCells);
  }

  List<int> entryCells(int k) => [
    for (final (r, c) in entries[k].cells) idx(r, c),
  ];

  /// [cell] hücresinden [dir] yönünde geçen giriş (yoksa null).
  int? entryAt(int cell, Dir dir) {
    for (final k in cellEntries[cell] ?? const <int>[]) {
      if (entries[k].dir == dir) return k;
    }
    return null;
  }

  /// Kare/klasik için standart numaralandırma: yatay veya dikey bir cevabın
  /// başladığı her hücreye soldan sağa, yukarıdan aşağıya sırayla numara verilir.
  static Map<int, int> numbering(
    int rows,
    int cols,
    bool Function(int r, int c) isLetter,
  ) {
    final result = <int, int>{};
    var n = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (!isLetter(r, c)) continue;
        final startsAcross =
            (c == 0 || !isLetter(r, c - 1)) &&
            c + 1 < cols &&
            isLetter(r, c + 1);
        final startsDown =
            (r == 0 || !isLetter(r - 1, c)) &&
            r + 1 < rows &&
            isLetter(r + 1, c);
        if (startsAcross || startsDown) result[r * cols + c] = ++n;
      }
    }
    return result;
  }
}
