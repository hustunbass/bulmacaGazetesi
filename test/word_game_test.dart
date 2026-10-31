import 'package:bulmaca_postasi/core/clock.dart';
import 'package:bulmaca_postasi/domain/play_timer.dart';
import 'package:bulmaca_postasi/domain/puzzle.dart';
import 'package:bulmaca_postasi/domain/word_game.dart';
import 'package:bulmaca_postasi/domain/word_structure.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

WordGame newGame(PuzzleType t) => WordGame(WordStructure.build(firstOf(t)));

void solveAll(WordGame g) {
  for (var i = 0; i < g.solution.length; i++) {
    if (g.solution[i].isEmpty) continue;
    g.selCell = i;
    g.inputLetter(g.solution[i]);
  }
}

void main() {
  test('cevaplar hücrelere doğru eşlenir; çengelde soru hücresi oynanamaz', () {
    final def = firstOf(PuzzleType.cengel);
    final s = WordStructure.build(def);
    for (final e in def.entries) {
      final cells = s.entryCells(s.entries.indexOf(e));
      expect(cells.length, e.length);
      expect(s.isPlayable(s.idx(e.clueRow, e.clueCol)), isFalse);
      for (var i = 0; i < cells.length; i++) {
        expect(s.isPlayable(cells[i]), isTrue);
      }
    }
    expect(s.clueCells, isNotEmpty);
  });

  test('kesişen hücre iki girişe aittir ve iki yön arasında geçiş yapılır', () {
    final s = WordStructure.build(firstOf(PuzzleType.kare));
    final cross = s.cellEntries.entries.firstWhere((e) => e.value.length == 2);
    final g = WordGame(s);
    g.tapCell(cross.key);
    final first = g.dir;
    g.tapCell(cross.key);
    expect(g.dir, first.other);
    g.tapCell(cross.key);
    expect(g.dir, first);
    // Aktif giriş, seçili yönle eşleşir.
    expect(s.entries[g.activeEntry!].dir, g.dir);
  });

  test(
    'tüm tür ve zorluklar yazılarak çözülebilir; yalnızca doğruysa tamamlanır',
    () {
      final lib = loadLibraryFromDisk();
      for (final def in lib.puzzles.where((p) => p.type.isWord)) {
        final g = WordGame(WordStructure.build(def));
        solveAll(g);
        expect(g.isSolved, isTrue, reason: def.id);
        expect(g.progress, 1.0);
      }
    },
  );

  test('yanlış harf tamamlanma sayılmaz; kontrol boşu yanlış saymaz', () {
    final g = newGame(PuzzleType.kare);
    solveAll(g);
    final cell = g.solution.indexWhere((s) => s.isNotEmpty);
    // Aynı çözüm hâlâ doğru → bir hücreyi yanlışla.
    g.letters[cell] = g.solution[cell] == 'Z' ? 'Y' : 'Z';
    expect(g.isSolved, isFalse);
    expect(g.progress, 1.0, reason: 'ilerleme doğruluğu sızdırmamalı');
    final r = g.checkAll();
    expect(r.wrong, 1);
    expect(r.empty, 0);
    expect(g.wrong, {cell});
    g.letters[cell] = '';
    final r2 = g.checkAll();
    expect(r2.wrong, 0);
    expect(r2.empty, 1);
  });

  test('kontrol doğru cevabı kendiliğinden yazmaz', () {
    final g = newGame(PuzzleType.cengel);
    g.selectEntry(0);
    g.checkEntry();
    expect(g.letters.every((l) => l.isEmpty), isTrue);
  });

  test('yalnızca geçerli Türkçe harf yazılır; Ş ve S ayrıdır', () {
    final g = newGame(PuzzleType.kare);
    g.selectEntry(0);
    final c = g.selCell;
    expect(g.inputLetter('5'), isFalse);
    expect(g.inputLetter('ab'), isFalse);
    expect(g.letters[c], '');
    g.inputLetter('ş');
    expect(g.letters[c], 'Ş');
    g.selCell = c;
    g.inputLetter('s');
    expect(g.letters[c], 'S');
  });

  test('geri silme ve yön tuşları tutarlı çalışır', () {
    final g = newGame(PuzzleType.kare);
    g.selectEntry(0);
    final cells = g.activeCells;
    g.inputLetter('A');
    g.inputLetter('B');
    expect(g.selCell, cells[2]);
    g.backspace(); // boş hücrede: önceki hücreye geçip siler
    expect(g.letters[cells[1]], '');
    expect(g.selCell, cells[1]);
    g.backspace();
    expect(g.letters[cells[0]], '');
  });

  test('geri al/yeniden yap; cevap temizleme tek işlemdir', () {
    final g = newGame(PuzzleType.kare);
    g.selectEntry(0);
    final cells = g.activeCells;
    for (final c in cells) {
      g.selCell = c;
      g.inputLetter('A');
    }
    g.selectEntry(0);
    expect(g.clearEntry(), cells.length);
    expect(cells.every((c) => g.letters[c].isEmpty), isTrue);
    expect(g.undo(), isTrue); // tek adımda hepsi geri gelir
    expect(cells.every((c) => g.letters[c] == 'A'), isTrue);
    expect(g.redo(), isTrue);
    expect(cells.every((c) => g.letters[c].isEmpty), isTrue);
  });

  test(
    'ipucu: harf ve cevap açılır, kilitlenir, silinemez ve geri alınamaz',
    () {
      final g = newGame(PuzzleType.kare);
      g.selectEntry(0);
      final cells = g.activeCells;
      g.selCell = cells[1];
      expect(g.hintLetter(), 1);
      expect(g.letters[cells[1]], g.solution[cells[1]]);
      expect(g.hinted[cells[1]], isTrue);
      expect(g.hintCount, 1);
      g.backspace();
      g.inputLetter('Q');
      expect(
        g.letters[cells[1]],
        g.solution[cells[1]],
        reason: 'kilitli hücre değişmez',
      );
      g.selectEntry(0);
      g.hintEntryAnswer();
      expect(cells.every((c) => g.letters[c] == g.solution[c]), isTrue);
      expect(g.hintCount, 2);
      // Geri al, yardım kaydını silemez.
      while (g.undo()) {}
      expect(g.hintedCellCount, cells.length);
      expect(g.hintCount, 2);
    },
  );

  test('ipucu, daha önce yazılıp geri alınacak hücreyi bozmaz', () {
    final g = newGame(PuzzleType.kare);
    g.selectEntry(0);
    final c = g.selCell;
    g.inputLetter('Q');
    g.selCell = c;
    g.hintLetter();
    g.undo();
    expect(g.letters[c], g.solution[c]);
  });

  test('tamamlanmış bulmacaya giriş yapılamaz', () {
    final g = newGame(PuzzleType.kare);
    solveAll(g);
    g.selCell = g.solution.indexWhere((s) => s.isNotEmpty);
    expect(g.inputLetter('Q'), isFalse);
    expect(g.isSolved, isTrue);
  });

  test('sıfırla girişleri, ipuçlarını ve sayaçları temizler', () {
    final g = newGame(PuzzleType.kare);
    solveAll(g);
    g.selectEntry(0);
    g.hintEntryAnswer();
    g.resetAll();
    expect(g.letters.every((l) => l.isEmpty), isTrue);
    expect(g.hintCount, 0);
    expect(g.hintedCellCount, 0);
    expect(g.canUndo, isFalse);
  });

  test('serileştirme ve geri yükleme birebirdir; bozuk durum reddedilir', () {
    final g = newGame(PuzzleType.cengel);
    g.selectEntry(1);
    g.inputLetter('Ğ');
    g.selectEntry(0);
    g.hintLetter();
    final j = g.toJson();
    final r = WordGame.fromJson(g.structure, j);
    expect(r.letters, g.letters);
    expect(r.hinted, g.hinted);
    expect(r.selCell, g.selCell);
    expect(r.hintCount, g.hintCount);
    final bad = Map<String, dynamic>.from(j)..['letters'] = ['A'];
    expect(() => WordGame.fromJson(g.structure, bad), throwsA(anything));
  });

  test(
    'anında geri bildirim: yanlış harf işaretlenir, doğru kelime tanınır',
    () {
      final g = newGame(PuzzleType.kare);
      g.selectEntry(0);
      final k = g.activeEntry!;
      final cells = g.activeCells;
      expect(g.correctEntries(), isEmpty);
      // Yanlış harf: hemen yanlış sayılır; boş hücre yanlış sayılmaz.
      g.selCell = cells.first;
      final wrong = g.solution[cells.first] == 'Z' ? 'Y' : 'Z';
      g.inputLetter(wrong);
      expect(g.isLetterWrong(cells.first), isTrue);
      expect(g.isLetterWrong(cells[1]), isFalse);
      expect(g.isEntryCorrect(k), isFalse);
      // Düzeltince yanlış kalkar; tüm harfler doğru olunca kelime doğru sayılır.
      for (final c in cells) {
        g.selCell = c;
        g.inputLetter(g.solution[c]);
      }
      expect(g.isLetterWrong(cells.first), isFalse);
      expect(g.isEntryCorrect(k), isTrue);
      expect(g.correctEntries(), contains(k));
      // Eksik bir harf kelimeyi doğru saymaz.
      g.selCell = cells.last;
      g.backspace();
      expect(g.isEntryCorrect(k), isFalse);
    },
  );

  test('ipucuyla kilitli hücre yazmayı durdurmaz: seçim üstünden geçer', () {
    final g = newGame(PuzzleType.kare);
    // En az 4 harfli bir cevap seç; ortadaki harfi ipucuyla aç.
    final k = List.generate(
      g.structure.entries.length,
      (i) => i,
    ).firstWhere((i) => g.structure.entryCells(i).length >= 4);
    g.selectEntry(k);
    final cells = g.activeCells;
    g.selCell = cells[2];
    g.hintLetter();
    g.selectEntry(k);
    g.selCell = cells.first;
    for (final c in cells) {
      if (g.hinted[c]) continue;
      expect(g.selCell == c || g.hinted[g.selCell], isTrue);
      g.inputLetter(g.solution[c]);
    }
    // Tüm kilitsiz hücreler yazıldı.
    expect(cells.every((c) => g.letters[c] == g.solution[c]), isTrue);
    // Geri silme de kilitli hücreyi atlar ve ilerler.
    g.selCell = cells[3];
    g.backspace();
    expect(g.letters[cells[3]], '');
    expect(g.hinted[cells[2]], isTrue);
  });

  test('seçimsiz (−1) hücreyle dokunma/ok işlemleri istisna fırlatmaz', () {
    final g = newGame(PuzzleType.cengel);
    expect(g.selCell, -1);
    expect(() => g.tapCell(-1), returnsNormally);
    expect(g.structure.isPlayable(-1), isFalse);
    expect(g.structure.isPlayable(100000), isFalse);
    expect(() => g.moveSelection(0, 1), returnsNormally);
    expect(g.inputLetter('A'), isFalse);
    expect(() => g.backspace(), returnsNormally);
  });

  test('tamamlanan bulmaca geri alınarak bozulamaz', () {
    final g = newGame(PuzzleType.kare);
    solveAll(g);
    expect(g.isSolved, isTrue);
    expect(g.canUndo, isFalse);
    expect(g.undo(), isFalse);
    expect(g.redo(), isFalse);
    expect(g.isSolved, isTrue);
  });

  test('süre yalnızca çalışırken işler ve saat değişiminden etkilenmez', () {
    final clock = FakeClock();
    final t = PlayTimer(clock);
    clock.advance(const Duration(minutes: 5));
    expect(t.elapsedMs, 0, reason: 'başlamadan işlemez');
    t.start();
    clock.advance(const Duration(seconds: 30));
    t.pause();
    clock.advance(const Duration(minutes: 10));
    expect(t.elapsedMs, 30000);
    t.start();
    t.start(); // ikinci start sayacı sıfırlamaz
    clock.advance(const Duration(seconds: 10));
    expect(t.elapsedMs, 40000);
  });
}
