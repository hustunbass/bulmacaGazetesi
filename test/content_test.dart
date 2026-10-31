import 'dart:convert';
import 'dart:io';

import 'package:bulmaca_postasi/data/content_library.dart';
import 'package:bulmaca_postasi/domain/puzzle.dart';
import 'package:bulmaca_postasi/domain/sudoku_solver.dart';
import 'package:bulmaca_postasi/domain/validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  bulkContentTests();
  final lib = loadLibraryFromDisk();

  test('paketlenmiş içeriğin tamamı doğrulamadan geçer', () {
    expect(lib.rejected, isEmpty);
    expect(ContentValidator.validatePool(lib.puzzles), isEmpty);
  });

  test('her kelime türünde en az dört bulmaca ve iki zorluk var', () {
    for (final t in [PuzzleType.cengel, PuzzleType.kare, PuzzleType.klasik]) {
      final list = lib.ofType(t);
      expect(list.length, greaterThanOrEqualTo(4), reason: t.key);
      expect(
        list.map((p) => p.difficulty).toSet().length,
        greaterThanOrEqualTo(2),
      );
    }
    expect(lib.ofType(PuzzleType.sudoku).length, greaterThanOrEqualTo(12));
  });

  test('klasik, kareden daha büyük ve yoğun; kategorileri çeşitli', () {
    final k = lib.ofType(PuzzleType.kare).first;
    final c = lib.ofType(PuzzleType.klasik).first;
    expect(c.rows * c.cols, greaterThan(k.rows * k.cols));
    expect(c.entries.length, greaterThan(k.entries.length));
    expect(
      c.entries.map((e) => e.category).toSet().length,
      greaterThanOrEqualTo(4),
    );
  });

  test(
    'her sudoku tek çözümlü ve zorluğu mantıksal derecelendirmeyle uyuşur',
    () {
      for (final p in lib.ofType(PuzzleType.sudoku)) {
        final g = SudokuSolver.parse(p.givens);
        final r = SudokuSolver.countSolutions(g, limit: 2);
        expect(r.count, 1, reason: p.id);
        expect(SudokuSolver.encode(r.first!), p.solution);
        expect(SudokuSolver.rate(g), p.difficulty, reason: p.id);
      }
    },
  );

  group('doğrulayıcı kötü içeriği yakalar', () {
    Map<String, dynamic> base() =>
        Map<String, dynamic>.from(decode(_raw('kare'))[0] as Map);

    ContentLibrary load(Map<String, dynamic> j) =>
        ContentLibrary.fromJsonDocuments([jsonEncode(j)]);

    test('kesişimi tutmayan cevap', () {
      final j = base();
      final grid = List<String>.from(j['grid'] as List);
      // İlk harf hücresini bozar.
      final r = grid.indexWhere((s) => s.contains(RegExp('[A-ZÇĞİÖŞÜ]')));
      final row = grid[r];
      final c = row.indexOf(RegExp('[A-ZÇĞİÖŞÜ]'));
      grid[r] = row.replaceRange(c, c + 1, row[c] == 'Z' ? 'Y' : 'Z');
      j['grid'] = grid;
      final l = load(j);
      expect(l.puzzles, isEmpty);
      expect(l.rejected.join(), contains('kesişim'));
    });

    test('yinelenen kimlik', () {
      final j = base();
      final l = ContentLibrary.fromJsonDocuments([
        jsonEncode(j),
        jsonEncode(j),
      ]);
      expect(l.puzzles.length, 1);
      expect(l.rejected.join(), contains('Yinelenen'));
    });

    test('bozuk JSON havuzu çökertmez', () {
      final l = ContentLibrary.fromJsonDocuments([
        '{bozuk',
        jsonEncode(base()),
      ]);
      expect(l.puzzles.length, 1);
      expect(l.rejected, isNotEmpty);
    });

    test('çözümsüz veya çok çözümlü sudoku reddedilir', () {
      final s = Map<String, dynamic>.from(decode(_raw('sudoku'))[0] as Map);
      s['givens'] = '0' * 81; // çok çözümlü
      final l = load(s);
      expect(l.puzzles, isEmpty);
    });

    test('çok uzun çengel ipucu reddedilir', () {
      final j = Map<String, dynamic>.from(decode(_raw('cengel'))[0] as Map);
      final es = (j['entries'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      es[0]['clue'] = 'x' * 200;
      j['entries'] = es;
      expect(load(j).puzzles, isEmpty);
    });

    test('ulaşılamayan cevap dizisi (eksik giriş) reddedilir', () {
      final j = base();
      final es = List.of(j['entries'] as List)..removeLast();
      j['entries'] = es;
      expect(load(j).puzzles, isEmpty);
    });
  });
}

String _raw(String name) =>
    File('assets/puzzles/$name.json').readAsStringSync();

void bulkContentTests() {
  test('her türde tam 100 bulmaca, benzersiz kimlik, üç zorluk', () {
    final lib = loadLibraryFromDisk();
    for (final t in PuzzleType.values) {
      final list = lib.ofType(t);
      expect(list.length, 100, reason: t.key);
      expect(list.map((p) => p.id).toSet().length, 100);
      expect(list.map((p) => p.difficulty).toSet().length, 3);
    }
    expect(lib.puzzles.length, 400);
  });

  test('kelime bulmacalarında aynı bulmaca iki kez yok (özdeş ızgara)', () {
    final lib = loadLibraryFromDisk();
    for (final t in [PuzzleType.cengel, PuzzleType.kare, PuzzleType.klasik]) {
      final grids = lib.ofType(t).map((p) => p.grid.join('/')).toSet();
      expect(grids.length, 100, reason: t.key);
    }
    final sud = lib.ofType(PuzzleType.sudoku).map((p) => p.givens).toSet();
    expect(sud.length, 100);
  });

  test('bir cevap bir türde aşırı tekrar etmez', () {
    final lib = loadLibraryFromDisk();
    for (final t in [PuzzleType.cengel, PuzzleType.kare, PuzzleType.klasik]) {
      final use = <String, int>{};
      for (final p in lib.ofType(t)) {
        for (final e in p.entries) {
          use[e.answer] = (use[e.answer] ?? 0) + 1;
        }
      }
      final worst = use.values.reduce((a, b) => a > b ? a : b);
      expect(
        worst,
        lessThanOrEqualTo(12),
        reason: '${t.key}: en çok tekrar $worst',
      );
    }
  });

  test('açılış: 400 bulmaca hafif doğrulamayla hızlı yüklenir', () {
    final docs = [
      for (final f in Directory('assets/puzzles').listSync().whereType<File>())
        if (f.path.endsWith('.json')) f.readAsStringSync(),
    ];
    final sw = Stopwatch()..start();
    final lib = ContentLibrary.fromJsonDocuments(docs, deep: false);
    sw.stop();
    expect(lib.puzzles.length, 400);
    // ignore: avoid_print
    print('Açılış yüklemesi (hafif doğrulama): ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });
}
