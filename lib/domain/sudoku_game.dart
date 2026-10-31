import 'puzzle.dart';
import 'puzzle_game.dart';
import 'sudoku_solver.dart';

class _Change {
  const _Change(
    this.cell,
    this.vBefore,
    this.nBefore,
    this.vAfter,
    this.nAfter,
  );
  final int cell;
  final int vBefore;
  final int nBefore;
  final int vAfter;
  final int nAfter;
}

/// Sudoku ipucu: gerçekten tespit edilmiş bir teknik varsa [explanation] dolu
/// gelir; aksi halde yalnızca "hücreyi aç" önerilir.
class SudokuHint {
  const SudokuHint(this.cell, this.digit, this.explanation);
  final int cell;
  final int digit;
  final String? explanation;
}

class SudokuGame implements PuzzleGame {
  SudokuGame(this.def)
    : given = SudokuSolver.parse(def.givens),
      solution = SudokuSolver.parse(def.solution) {
    values = List<int>.from(given);
    notes = List<int>.filled(81, 0);
  }

  factory SudokuGame.fromJson(PuzzleDefinition def, Map<String, dynamic> j) {
    final g = SudokuGame(def);
    final v = j['values'], n = j['notes'], h = j['hinted'];
    if (v is! List ||
        v.length != 81 ||
        n is! List ||
        n.length != 81 ||
        h is! List) {
      throw CorruptStateException('Sudoku durumu eksik');
    }
    for (var i = 0; i < 81; i++) {
      final x = v[i], y = n[i];
      if (x is! int || x < 0 || x > 9 || y is! int || y < 0 || y > 0x1FF) {
        throw CorruptStateException('Geçersiz değer (hücre $i)');
      }
      if (g.given[i] != 0 && x != g.given[i]) {
        throw CorruptStateException('Başlangıç sayısı değişmiş (hücre $i)');
      }
      g.values[i] = x;
      g.notes[i] = x == 0 ? y : 0;
    }
    for (final i in h) {
      if (i is! int || i < 0 || i >= 81 || g.given[i] != 0) {
        throw CorruptStateException('Geçersiz ipucu hücresi');
      }
      g.hinted.add(i);
      g.values[i] = g.solution[i];
      g.notes[i] = 0;
    }
    final sel = j['sel'];
    g.selCell = sel is int && sel >= -1 && sel < 81 ? sel : -1;
    g.noteMode = j['noteMode'] == true;
    g.hintCount = (j['hints'] as int?) ?? 0;
    g.checkCount = (j['checks'] as int?) ?? 0;
    return g;
  }

  final PuzzleDefinition def;
  final List<int> given;
  final List<int> solution;
  late final List<int> values;
  late final List<int> notes;
  final Set<int> hinted = {};
  int selCell = -1;
  bool noteMode = false;
  @override
  int hintCount = 0;
  @override
  int checkCount = 0;

  final List<List<_Change>> _undo = [];
  final List<List<_Change>> _redo = [];

  bool isGiven(int i) => given[i] != 0;
  bool isLocked(int i) => given[i] != 0 || hinted.contains(i);

  @override
  int get hintedCellCount => hinted.length;
  @override
  bool get canUndo => !isSolved && _undo.isNotEmpty;
  @override
  bool get canRedo => !isSolved && _redo.isNotEmpty;

  @override
  double get progress {
    var empties = 0, filled = 0;
    for (var i = 0; i < 81; i++) {
      if (given[i] != 0) continue;
      empties++;
      if (values[i] != 0) filled++;
    }
    return empties == 0 ? 1 : filled / empties;
  }

  /// Tüm kurallar doğrulanır: dolu olmak yetmez, çakışma da olmamalıdır.
  @override
  bool get isSolved => !values.contains(0) && !SudokuSolver.hasConflict(values);

  /// Kurallara aykırı (satır/sütun/bölgede tekrar eden) hücreler.
  Set<int> get conflicts => SudokuSolver.conflicts(values);

  /// [d] rakamının doğru yerleştirilmiş sayısı (9 olunca takımda tamamlanır).
  int placedCorrect(int d) {
    var n = 0;
    for (var i = 0; i < 81; i++) {
      if (values[i] == d && solution[i] == d) n++;
    }
    return n;
  }

  bool digitDone(int d) => placedCorrect(d) == 9;

  void select(int i) => selCell = i;

  void moveSelection(int dr, int dc) {
    if (selCell < 0) {
      selCell = 0;
      return;
    }
    final r = (selCell ~/ 9 + dr).clamp(0, 8);
    final c = (selCell % 9 + dc).clamp(0, 8);
    selCell = r * 9 + c;
  }

  void toggleNoteMode() => noteMode = !noteMode;

  void _commit(List<_Change> group) {
    if (group.isEmpty) return;
    for (final c in group) {
      values[c.cell] = c.vAfter;
      notes[c.cell] = c.nAfter;
    }
    _undo.add(group);
    _redo.clear();
  }

  /// [autoClear]: yerleştirilen rakamı aynı satır/sütun/bölgedeki notlardan
  /// temizler (tek geri alma adımı içinde).
  bool inputDigit(int d, {bool autoClear = false}) {
    if (d < 1 || d > 9 || selCell < 0 || isLocked(selCell) || isSolved) {
      return false;
    }
    final i = selCell;
    if (noteMode) {
      if (values[i] != 0) return false;
      _commit([_Change(i, 0, notes[i], 0, notes[i] ^ SudokuSolver.bit(d))]);
      return true;
    }
    final group = <_Change>[];
    if (values[i] != d || notes[i] != 0) {
      group.add(_Change(i, values[i], notes[i], d, 0));
    }
    if (autoClear) {
      final bit = SudokuSolver.bit(d);
      for (final p in SudokuSolver.peers[i]) {
        if (p != i && values[p] == 0 && notes[p] & bit != 0) {
          group.add(_Change(p, 0, notes[p], 0, notes[p] & ~bit));
        }
      }
    }
    _commit(group);
    return true;
  }

  /// Dolu hücrede değeri, boşta notları siler.
  bool erase() {
    if (selCell < 0 || isLocked(selCell) || isSolved) return false;
    final i = selCell;
    if (values[i] != 0) {
      _commit([_Change(i, values[i], 0, 0, 0)]);
      return true;
    }
    if (notes[i] != 0) {
      _commit([_Change(i, 0, notes[i], 0, 0)]);
      return true;
    }
    return false;
  }

  bool undo() {
    if (isSolved) return false;
    while (_undo.isNotEmpty) {
      final g = _undo.removeLast();
      final ok = [
        for (final c in g)
          if (!hinted.contains(c.cell)) c,
      ];
      if (ok.isEmpty) continue;
      for (final c in ok.reversed) {
        values[c.cell] = c.vBefore;
        notes[c.cell] = c.nBefore;
      }
      _redo.add(ok);
      selCell = ok.first.cell;
      return true;
    }
    return false;
  }

  bool redo() {
    if (isSolved) return false;
    while (_redo.isNotEmpty) {
      final g = _redo.removeLast();
      final ok = [
        for (final c in g)
          if (!hinted.contains(c.cell)) c,
      ];
      if (ok.isEmpty) continue;
      for (final c in ok) {
        values[c.cell] = c.vAfter;
        notes[c.cell] = c.nAfter;
      }
      _undo.add(ok);
      selCell = ok.first.cell;
      return true;
    }
    return false;
  }

  /// Seçili hücre için ipucu önerisi (uygulamaz). Açıklama yalnızca kullanıcı
  /// girişlerinin doğru olanları ve başlangıç sayıları üzerinden tespit
  /// edilebilen gerçek bir teknikse üretilir.
  SudokuHint? previewHint() {
    final i = selCell;
    if (i < 0 || isLocked(i)) return null;
    final trusted = [
      for (var k = 0; k < 81; k++)
        given[k] != 0 || values[k] == solution[k] ? solution[k] : 0,
    ];
    final ex = SudokuLogic.explain(trusted, i, solution[i]);
    return SudokuHint(i, solution[i], ex?.text);
  }

  /// Hücreyi açar ve kilitler; sayılır, geri alınamaz.
  bool applyHint() {
    final i = selCell;
    if (i < 0 || isLocked(i)) return false;
    values[i] = solution[i];
    notes[i] = 0;
    hinted.add(i);
    final bit = SudokuSolver.bit(solution[i]);
    for (final p in SudokuSolver.peers[i]) {
      if (values[p] == 0) notes[p] &= ~bit;
    }
    hintCount++;
    return true;
  }

  /// Kurallara aykırı hücre sayısı (cevap anahtarına göre değil).
  CheckResult check() {
    checkCount++;
    final bad = conflicts.where((i) => !isGiven(i)).length;
    var empty = 0, ok = 0;
    for (var i = 0; i < 81; i++) {
      if (given[i] != 0) continue;
      if (values[i] == 0) {
        empty++;
      } else {
        ok++;
      }
    }
    return CheckResult(correct: ok - bad, wrong: bad, empty: empty);
  }

  void resetAll() {
    for (var i = 0; i < 81; i++) {
      values[i] = given[i];
      notes[i] = 0;
    }
    hinted.clear();
    _undo.clear();
    _redo.clear();
    hintCount = checkCount = 0;
    selCell = -1;
    noteMode = false;
  }

  @override
  Map<String, dynamic> toJson() => {
    'values': values,
    'notes': notes,
    'hinted': hinted.toList()..sort(),
    'sel': selCell,
    'noteMode': noteMode,
    'hints': hintCount,
    'checks': checkCount,
  };
}
