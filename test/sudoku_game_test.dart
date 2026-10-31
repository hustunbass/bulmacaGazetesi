import 'package:bulmaca_postasi/domain/puzzle.dart';
import 'package:bulmaca_postasi/domain/sudoku_game.dart';
import 'package:bulmaca_postasi/domain/sudoku_generator.dart';
import 'package:bulmaca_postasi/domain/sudoku_solver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

SudokuGame game([Difficulty? d]) {
  final lib = loadLibraryFromDisk();
  final def = lib
      .ofType(PuzzleType.sudoku)
      .firstWhere((p) => d == null || p.difficulty == d);
  return SudokuGame(def);
}

void fillAll(SudokuGame g) {
  for (var i = 0; i < 81; i++) {
    if (g.isGiven(i)) continue;
    g.select(i);
    g.inputDigit(g.solution[i]);
  }
}

void main() {
  test('başlangıç sayıları değiştirilemez', () {
    final g = game();
    final i = List.generate(81, (k) => k).firstWhere(g.isGiven);
    g.select(i);
    final before = g.values[i];
    expect(g.inputDigit(before % 9 + 1), isFalse);
    expect(g.erase(), isFalse);
    expect(g.values[i], before);
  });

  test('tam çözüm yalnızca tüm kurallar sağlanınca başarı sayılır', () {
    final g = game();
    expect(g.isSolved, isFalse);
    fillAll(g);
    expect(g.isSolved, isTrue);
  });

  test('dolu ama çakışan tahta başarı sayılmaz', () {
    final g = game();
    // Son boş hücre dışındakileri doğru doldur; sonuncuya yanlış (ama dolu) yaz.
    final empties = [
      for (var k = 0; k < 81; k++)
        if (!g.isGiven(k)) k,
    ];
    for (final k in empties.take(empties.length - 1)) {
      g.select(k);
      g.inputDigit(g.solution[k]);
    }
    final i = empties.last;
    g.select(i);
    // Yanlış ama dolu: aynı satırdaki başka bir rakam.
    final r = i ~/ 9;
    final other = g.solution[r * 9 + (i % 9 + 1) % 9];
    g.inputDigit(other);
    expect(g.values.contains(0), isFalse);
    expect(g.isSolved, isFalse);
    expect(g.conflicts, isNotEmpty);
  });

  test('not modu: adaylar eklenir/çıkarılır, değer yazınca notlar silinir', () {
    final g = game();
    final i = List.generate(81, (k) => k).firstWhere((k) => !g.isGiven(k));
    g.select(i);
    g.toggleNoteMode();
    g.inputDigit(3);
    g.inputDigit(5);
    expect(g.notes[i], SudokuSolver.bit(3) | SudokuSolver.bit(5));
    g.inputDigit(3);
    expect(g.notes[i], SudokuSolver.bit(5));
    g.toggleNoteMode();
    g.inputDigit(7);
    expect(g.values[i], 7);
    expect(g.notes[i], 0);
    g.undo();
    expect(g.values[i], 0);
    expect(
      g.notes[i],
      SudokuSolver.bit(5),
      reason: 'geri al notları geri getirir',
    );
  });

  test('otomatik aday temizleme tek geri alma adımıdır', () {
    final g = game();
    final i = List.generate(81, (k) => k).firstWhere((k) => !g.isGiven(k));
    final peer = SudokuSolver.peers[i].firstWhere(
      (p) => p != i && !g.isGiven(p),
    );
    final d = g.solution[i];
    g.select(peer);
    g.toggleNoteMode();
    g.inputDigit(d);
    g.toggleNoteMode();
    expect(g.notes[peer] & SudokuSolver.bit(d), isNot(0));
    g.select(i);
    g.inputDigit(d, autoClear: true);
    expect(g.notes[peer] & SudokuSolver.bit(d), 0);
    g.undo();
    expect(g.values[i], 0);
    expect(g.notes[peer] & SudokuSolver.bit(d), isNot(0));
    g.redo();
    expect(g.values[i], d);
    expect(g.notes[peer] & SudokuSolver.bit(d), 0);
  });

  test('sayı takımı: dokuz doğru yerleşimde rakam tamamlanır', () {
    final g = game();
    expect(g.digitDone(1), isFalse);
    fillAll(g);
    for (var d = 1; d <= 9; d++) {
      expect(g.digitDone(d), isTrue);
    }
  });

  test('yanlış rakamlar "doğru yerleşim" sayılmaz', () {
    final g = game();
    final i = List.generate(81, (k) => k).firstWhere((k) => !g.isGiven(k));
    g.select(i);
    final wrong = g.solution[i] % 9 + 1;
    g.inputDigit(wrong);
    expect(g.placedCorrect(wrong), lessThan(9));
    expect(g.values[i], wrong);
  });

  test('ipucu: hücre açılır, kilitlenir, geri alınamaz; sayaç artar', () {
    final g = game();
    final i = List.generate(81, (k) => k).firstWhere((k) => !g.isGiven(k));
    g.select(i);
    final h = g.previewHint()!;
    expect(h.digit, g.solution[i]);
    expect(g.applyHint(), isTrue);
    expect(g.hintCount, 1);
    expect(g.values[i], g.solution[i]);
    expect(g.isLocked(i), isTrue);
    expect(g.erase(), isFalse);
    while (g.undo()) {}
    expect(g.values[i], g.solution[i]);
    expect(g.hintCount, 1);
  });

  test('açıklamalı ipucu yalnızca gerçekten tespit edilen tekniği anlatır', () {
    // Çok boş bir tahtada tek aday yoktur → açıklama üretilmemelidir.
    final lib = loadLibraryFromDisk();
    final hard = lib
        .ofType(PuzzleType.sudoku)
        .firstWhere((p) => p.difficulty == Difficulty.zor);
    final g = SudokuGame(hard);
    var explained = 0, bare = 0;
    for (var i = 0; i < 81; i++) {
      if (g.isGiven(i)) continue;
      g.select(i);
      final h = g.previewHint()!;
      if (h.explanation == null) {
        bare++;
      } else {
        explained++;
        // Açıklama varsa verilen rakam gerçekten çözümdür ve tek adaydır ya da tek yerdir.
        expect(h.digit, g.solution[i]);
        final cand = SudokuSolver.candidates(g.values)[i];
        final single = cand == SudokuSolver.bit(h.digit);
        expect(single || h.explanation!.contains('tek boş'), isTrue);
      }
    }
    expect(explained + bare, greaterThan(0));
  });

  test('kontrol kurallara aykırılığı bildirir, boşları yanlış saymaz', () {
    final g = game();
    var r = g.check();
    expect(r.wrong, 0);
    expect(r.empty, greaterThan(0));
    final i = List.generate(81, (k) => k).firstWhere((k) => !g.isGiven(k));
    final row = i ~/ 9;
    final clash = List.generate(
      9,
      (c) => row * 9 + c,
    ).firstWhere((k) => g.isGiven(k));
    g.select(i);
    g.inputDigit(g.given[clash]);
    r = g.check();
    expect(r.wrong, greaterThanOrEqualTo(1));
    expect(g.checkCount, 2);
  });

  test('sıfırla başlangıç sayılarını korur, gerisini temizler', () {
    final g = game();
    fillAll(g);
    g.resetAll();
    expect(g.values, g.given);
    expect(g.notes.every((n) => n == 0), isTrue);
    expect(g.hintCount, 0);
  });

  test(
    'serileştirme gidiş-dönüş; değiştirilmiş başlangıç sayısı reddedilir',
    () {
      final g = game();
      final i = List.generate(81, (k) => k).firstWhere((k) => !g.isGiven(k));
      g.select(i);
      g.toggleNoteMode();
      g.inputDigit(2);
      final r = SudokuGame.fromJson(g.def, g.toJson());
      expect(r.notes, g.notes);
      expect(r.noteMode, isTrue);
      final j = g.toJson();
      final vals = List<int>.from(j['values'] as List);
      final gi = List.generate(81, (k) => k).firstWhere(g.isGiven);
      vals[gi] = vals[gi] % 9 + 1;
      expect(
        () => SudokuGame.fromJson(g.def, {...j, 'values': vals}),
        throwsA(anything),
      );
    },
  );

  test('tamamlanan sudoku geri alınarak bozulamaz', () {
    final g = game();
    fillAll(g);
    expect(g.isSolved, isTrue);
    expect(g.canUndo, isFalse);
    expect(g.undo(), isFalse);
    expect(g.isSolved, isTrue);
  });

  test('paketlenmiş sudokular bağımsız olarak tek çözümlüdür', () {
    final lib = loadLibraryFromDisk();
    for (final p in lib.ofType(PuzzleType.sudoku)) {
      final r = SudokuSolver.countSolutions(
        SudokuSolver.parse(p.givens),
        limit: 2,
      );
      expect(r.count, 1, reason: p.id);
      expect(r.exhausted, isFalse);
    }
  });

  test(
    'yerel üretici: tek çözüm, istenen zorluk, deneme sınırı içinde biter',
    () {
      for (final d in Difficulty.values) {
        final g = generateSudoku(d, 12345 + d.index);
        expect(g, isNotNull, reason: d.key);
        final grid = SudokuSolver.parse(g!.givens);
        final r = SudokuSolver.countSolutions(grid, limit: 2);
        expect(r.count, 1);
        expect(SudokuSolver.encode(r.first!), g.solution);
        expect(SudokuSolver.rate(grid), d);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
