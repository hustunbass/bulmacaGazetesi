import '../core/turkish.dart';
import 'puzzle.dart';
import 'puzzle_game.dart';
import 'word_structure.dart';

class _Change {
  const _Change(this.cell, this.before, this.after);
  final int cell;
  final String before;
  final String after;
}

/// Çengel, kare ve klasik bulmacalar için ortak oyun motoru.
class WordGame implements PuzzleGame {
  WordGame(this.structure)
    : letters = List.filled(structure.rows * structure.cols, ''),
      hinted = List.filled(structure.rows * structure.cols, false),
      solution = [
        for (final row in structure.def.grid)
          ...() {
            final l = Turkish.letters(row);
            return [
              for (var c = 0; c < structure.cols; c++)
                c < l.length && l[c] != '#' ? l[c] : '',
            ];
          }(),
      ] {
    _playableCount = solution.where((s) => s.isNotEmpty).length;
  }

  factory WordGame.fromJson(WordStructure s, Map<String, dynamic> j) {
    final g = WordGame(s);
    final n = g.letters.length;
    final l = j['letters'];
    if (l is! List || l.length != n) {
      throw CorruptStateException('Harf listesi ızgarayla uyuşmuyor');
    }
    for (var i = 0; i < n; i++) {
      final v = l[i];
      if (v is! String || (v.isNotEmpty && Turkish.inputLetter(v) != v)) {
        throw CorruptStateException('Geçersiz harf (hücre $i)');
      }
      if (v.isNotEmpty && g.solution[i].isEmpty) {
        throw CorruptStateException('Oynanamaz hücrede harf var ($i)');
      }
      g.letters[i] = v;
    }
    final h = j['hinted'];
    if (h is! List) throw CorruptStateException('İpucu listesi eksik');
    for (final i in h) {
      if (i is! int || i < 0 || i >= n || g.solution[i].isEmpty) {
        throw CorruptStateException('Geçersiz ipucu hücresi');
      }
      g.hinted[i] = true;
      g.letters[i] = g.solution[i];
    }
    final sel = j['sel'];
    g.selCell = sel is int && sel >= -1 && sel < n ? sel : -1;
    g.dir = Dir.parse(j['dir'] ?? 'A');
    g.hintLetters = (j['hl'] as int?) ?? 0;
    g.hintAnswers = (j['ha'] as int?) ?? 0;
    g.checkCount = (j['checks'] as int?) ?? 0;
    return g;
  }

  final WordStructure structure;
  final List<String> letters;
  final List<bool> hinted;

  /// Cevap anahtarı (hücre başına harf; oynanamaz hücre = ''). İstemcide
  /// bulunur; "hileye karşı güvenli" değildir.
  final List<String> solution;

  /// Son kontrolün yanlış bulduğu hücreler (düzenlenince temizlenir).
  final Set<int> wrong = {};

  late final int _playableCount;
  int selCell = -1;
  Dir dir = Dir.across;
  int hintLetters = 0;
  int hintAnswers = 0;
  @override
  int checkCount = 0;

  final List<List<_Change>> _undo = [];
  final List<List<_Change>> _redo = [];

  PuzzleDefinition get def => structure.def;

  @override
  int get hintCount => hintLetters + hintAnswers;

  @override
  int get hintedCellCount => hinted.where((e) => e).length;

  @override
  bool get canUndo => !isSolved && _undo.isNotEmpty;
  @override
  bool get canRedo => !isSolved && _redo.isNotEmpty;

  @override
  double get progress {
    var f = 0;
    for (var i = 0; i < letters.length; i++) {
      if (solution[i].isNotEmpty && letters[i].isNotEmpty) f++;
    }
    return _playableCount == 0 ? 0 : f / _playableCount;
  }

  @override
  bool get isSolved {
    for (var i = 0; i < letters.length; i++) {
      if (solution[i].isNotEmpty && letters[i] != solution[i]) return false;
    }
    return _playableCount > 0;
  }

  int? get activeEntry => selCell < 0 ? null : structure.entryAt(selCell, dir);

  List<int> get activeCells {
    final k = activeEntry;
    return k == null ? const [] : structure.entryCells(k);
  }

  // ---- Seçim ----

  /// Harf hücresine dokunma. İki yönlü hücrede ikinci dokunuş yönü değiştirir.
  void tapCell(int cell) {
    if (cell < 0 || !structure.isPlayable(cell)) return;
    if (cell == selCell) {
      final o = dir.other;
      if (structure.entryAt(cell, o) != null) dir = o;
      return;
    }
    selCell = cell;
    if (structure.entryAt(cell, dir) == null) {
      final o = dir.other;
      if (structure.entryAt(cell, o) != null) dir = o;
    }
  }

  /// Bir girişi etkinleştirir; ilk boş (yoksa ilk) hücreye gider.
  void selectEntry(int k) {
    final cells = structure.entryCells(k);
    dir = structure.entries[k].dir;
    selCell = cells.firstWhere(
      (c) => letters[c].isEmpty,
      orElse: () => cells.first,
    );
  }

  void moveSelection(int dr, int dc) {
    if (selCell < 0) return;
    var r = selCell ~/ structure.cols, c = selCell % structure.cols;
    for (var i = 0; i < structure.rows + structure.cols; i++) {
      r += dr;
      c += dc;
      if (r < 0 || c < 0 || r >= structure.rows || c >= structure.cols) return;
      final idx = structure.idx(r, c);
      if (structure.isPlayable(idx)) {
        selCell = idx;
        final want = dr != 0 ? Dir.down : Dir.across;
        if (structure.entryAt(idx, want) != null) dir = want;
        return;
      }
    }
  }

  /// Sonraki (+1) veya önceki (−1) giriş.
  void stepEntry(int delta) {
    final n = structure.entries.length;
    if (n == 0) return;
    final cur = activeEntry ?? (delta > 0 ? n - 1 : 0);
    selectEntry((cur + delta + n) % n);
  }

  // ---- Düzenleme ----

  void _commit(List<_Change> group) {
    if (group.isEmpty) return;
    for (final ch in group) {
      letters[ch.cell] = ch.after;
      wrong.remove(ch.cell);
    }
    _undo.add(group);
    _redo.clear();
  }

  /// Seçili hücreye harf yazar; geçerli bir Türkçe harf değilse yok sayar.
  /// Yazıldıysa true döner.
  bool inputLetter(String raw) {
    final ch = Turkish.inputLetter(raw);
    if (ch == null || selCell < 0 || hinted[selCell] || isSolved) return false;
    if (solution[selCell].isEmpty) return false;
    final before = letters[selCell];
    if (before != ch) _commit([_Change(selCell, before, ch)]);
    _advance(1);
    return true;
  }

  void _advance(int step) {
    final cells = activeCells;
    final i = cells.indexOf(selCell);
    if (i < 0) return;
    var j = i + step;
    if (j < 0 || j >= cells.length) return;
    // İpucuyla kilitlenmiş hücrelerin üzerinden geç; yazma/silme durmasın.
    while (j + step >= 0 && j + step < cells.length && hinted[cells[j]]) {
      j += step;
    }
    selCell = cells[j];
  }

  /// Geri silme: dolu hücreyi siler; boşsa önceki hücreye geçip onu siler.
  void backspace() {
    if (selCell < 0 || isSolved) return;
    if (letters[selCell].isNotEmpty && !hinted[selCell]) {
      _commit([_Change(selCell, letters[selCell], '')]);
      return;
    }
    _advance(-1);
    if (letters[selCell].isNotEmpty && !hinted[selCell]) {
      _commit([_Change(selCell, letters[selCell], '')]);
    }
  }

  /// Seçili cevabın kilitsiz harflerini tek işlem olarak temizler.
  int clearEntry() {
    if (isSolved) return 0;
    final group = [
      for (final c in activeCells)
        if (letters[c].isNotEmpty && !hinted[c]) _Change(c, letters[c], ''),
    ];
    _commit(group);
    return group.length;
  }

  bool undo() {
    if (isSolved) return false;
    while (_undo.isNotEmpty) {
      final g = _undo.removeLast();
      // İpucuyla kilitlenmiş hücreler geri alınarak bozulmaz.
      final applicable = [
        for (final c in g)
          if (!hinted[c.cell]) c,
      ];
      if (applicable.isEmpty) continue;
      for (final c in applicable.reversed) {
        letters[c.cell] = c.before;
        wrong.remove(c.cell);
      }
      _redo.add(applicable);
      selCell = applicable.first.cell;
      return true;
    }
    return false;
  }

  bool redo() {
    if (isSolved) return false;
    while (_redo.isNotEmpty) {
      final g = _redo.removeLast();
      final applicable = [
        for (final c in g)
          if (!hinted[c.cell]) c,
      ];
      if (applicable.isEmpty) continue;
      for (final c in applicable) {
        letters[c.cell] = c.after;
        wrong.remove(c.cell);
      }
      _undo.add(applicable);
      selCell = applicable.first.cell;
      return true;
    }
    return false;
  }

  // ---- İpucu ----

  /// Seçili harfi açar ve kilitler. Açılan hücre sayısını döndürür.
  int hintLetter() {
    if (selCell < 0 || hinted[selCell] || solution[selCell].isEmpty) return 0;
    _reveal(selCell);
    hintLetters++;
    return 1;
  }

  /// Seçili cevabın tüm harflerini açar.
  int hintEntryAnswer() {
    var n = 0;
    for (final c in activeCells) {
      if (!hinted[c]) {
        _reveal(c);
        n++;
      }
    }
    if (n > 0) hintAnswers++;
    return n;
  }

  void _reveal(int c) {
    letters[c] = solution[c];
    hinted[c] = true;
    wrong.remove(c);
  }

  // ---- Anında geri bildirim ----

  /// Bu hücredeki harf cevap anahtarına göre yanlış mı (boş hücre yanlış değil).
  bool isLetterWrong(int i) =>
      letters[i].isNotEmpty &&
      solution[i].isNotEmpty &&
      letters[i] != solution[i];

  /// [k]. cevabın tüm harfleri doğru yazılmış mı.
  bool isEntryCorrect(int k) =>
      structure.entryCells(k).every((c) => letters[c] == solution[c]);

  /// Tüm harfleri doğru yazılmış cevapların indeksleri.
  List<int> correctEntries() => [
    for (var k = 0; k < structure.entries.length; k++)
      if (isEntryCorrect(k)) k,
  ];

  // ---- Kontrol ----

  CheckResult _check(Iterable<int> cells) {
    wrong.clear();
    var ok = 0, bad = 0, empty = 0;
    for (final c in cells) {
      if (solution[c].isEmpty) continue;
      if (letters[c].isEmpty) {
        empty++;
      } else if (letters[c] == solution[c]) {
        ok++;
      } else {
        bad++;
        wrong.add(c);
      }
    }
    checkCount++;
    return CheckResult(correct: ok, wrong: bad, empty: empty);
  }

  CheckResult checkEntry() => _check(activeCells);

  CheckResult checkAll() => _check(List.generate(letters.length, (i) => i));

  // ---- Sıfırlama ----

  /// Girişleri, ipuçlarını ve geçmişi temizler (bulmaca değişmez).
  void resetAll() {
    for (var i = 0; i < letters.length; i++) {
      letters[i] = '';
      hinted[i] = false;
    }
    wrong.clear();
    _undo.clear();
    _redo.clear();
    hintLetters = hintAnswers = checkCount = 0;
    selCell = -1;
    dir = Dir.across;
  }

  @override
  Map<String, dynamic> toJson() => {
    'letters': letters,
    'hinted': [
      for (var i = 0; i < hinted.length; i++)
        if (hinted[i]) i,
    ],
    'sel': selCell,
    'dir': dir.key,
    'hl': hintLetters,
    'ha': hintAnswers,
    'checks': checkCount,
  };
}
