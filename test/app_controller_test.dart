import 'dart:io';

import 'package:bulmaca_postasi/core/clock.dart';
import 'package:bulmaca_postasi/data/content_library.dart';
import 'package:bulmaca_postasi/data/file_store.dart';
import 'package:bulmaca_postasi/domain/puzzle.dart';
import 'package:bulmaca_postasi/domain/sudoku_game.dart';
import 'package:bulmaca_postasi/domain/word_game.dart';
import 'package:bulmaca_postasi/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

late Directory dir;
late FakeClock clock;
DateTime now = DateTime(2026, 10, 30, 9);

Future<AppController> open({ContentLibrary? lib}) async {
  final c = AppController(
    store: FileStore(dir),
    library: lib ?? loadLibraryFromDisk(),
    clock: clock,
    now: () => now,
  );
  await c.init();
  return c;
}

/// Uygulamanın kapatılıp açılmasını taklit eder: yazmalar diske iner.
Future<AppController> restart(AppController c) async {
  await c.onBackground();
  c.dispose();
  return open();
}

void solve(AttemptSessionLike s) => s.solveIt();

typedef AttemptSessionLike = _Solver;

class _Solver {
  _Solver(this.s);
  final dynamic s;
  void solveIt() {
    s.activate();
    s.mutate(() {
      final WordGame? w = s.word;
      final SudokuGame? su = s.sudoku;
      if (w != null) {
        for (var i = 0; i < w.solution.length; i++) {
          if (w.solution[i].isEmpty) continue;
          w.selCell = i;
          w.inputLetter(w.solution[i]);
        }
      } else if (su != null) {
        for (var i = 0; i < 81; i++) {
          if (su.isGiven(i)) continue;
          su.select(i);
          su.inputDigit(su.solution[i]);
        }
      }
    });
  }
}

void main() {
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bulmaca_test');
    clock = FakeClock();
    now = DateTime(2026, 10, 30, 9);
  });
  tearDown(() async {
    // Bekleyen arka plan yazmaları bitsin; temizlik hatası testi bozmasın.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // geçici dizin; işletim sistemi temizler
    }
  });

  test(
    'ilk açılışta en az dört sayfa, her sayfada iki farklı yuva kurulur',
    () async {
      final c = await open();
      expect(c.fatalError, isNull);
      final iss = c.issue!;
      expect(iss.pages.length, greaterThanOrEqualTo(4));
      for (final p in iss.pages) {
        expect(p.slots.length, 2);
        for (final s in p.slots) {
          expect(c.sessionFor(s), isNotNull);
        }
      }
      expect(iss.id, '2026-10-30');
      c.dispose();
    },
  );

  test(
    'aynı gün yeniden açılınca aynı içerik ve aynı denemeler gelir',
    () async {
      final c = await open();
      final ids = [
        for (final s in c.issue!.slots)
          '${s.attemptId}|${c.sessionFor(s)!.def.id}',
      ];
      final c2 = await restart(c);
      final ids2 = [
        for (final s in c2.issue!.slots)
          '${s.attemptId}|${c2.sessionFor(s)!.def.id}',
      ];
      expect(ids2, ids);
      c2.dispose();
    },
  );

  test('yaz → kapat/aç → aynı ilerleme ve süre geri gelir', () async {
    final c = await open();
    final slot = c.issue!.pages[1].slots[0];
    final s = c.sessionFor(slot)!;
    final w = s.word;
    expect(w, isNotNull, reason: 'sayfa 2 ilk yuvası kelime bulmacası olmalı');
    s.activate();
    clock.advance(const Duration(seconds: 42));
    s.mutate(() {
      w!.selectEntry(0);
      w.inputLetter('Ş');
    });
    final cell = w!.letters.indexOf('Ş');
    expect(cell, isNonNegative);
    final c2 = await restart(c);
    final s2 = c2.sessionFor(c2.issue!.pages[1].slots[0])!;
    expect(s2.word!.letters[cell], 'Ş');
    expect(s2.elapsedMs, 42000);
    c2.dispose();
  });

  test('son hücreye yapılan giriş de kayda geçer (arka plana geçiş)', () async {
    final c = await open();
    final sudokuSlot = c.issue!.slots.firstWhere(
      (x) => c.sessionFor(x)!.def.type == PuzzleType.sudoku,
    );
    final s = c.sessionFor(sudokuSlot)!;
    final su = s.sudoku!;
    final i = List.generate(81, (k) => k).lastWhere((k) => !su.isGiven(k));
    s.mutate(() {
      su.select(i);
      su.inputDigit(su.solution[i]);
    });
    final c2 = await restart(c);
    final s2 = c2.sessionFor(
      c2.issue!.slots.firstWhere((x) => x.id == sudokuSlot.id),
    )!;
    expect(s2.sudoku!.values[i], su.solution[i]);
    c2.dispose();
  });

  test(
    'birinci bulmacayı değiştirince ikincisi aynen kalır; öncekiler arşivlenir',
    () async {
      final c = await open();
      final page = c.issue!.pages[0];
      final other = c.sessionFor(page.slots[1])!;
      other.mutate(() {
        other.game is SudokuGame
            ? (other.game as SudokuGame).select(0)
            : (other.game as WordGame).tapCell(
                (other.game as WordGame).solution.indexWhere(
                  (e) => e.isNotEmpty,
                ),
              );
      });
      final otherJson = other.toJson().toString();
      final firstId = c.sessionFor(page.slots[0])!.def.id;
      final oldAttempt = page.slots[0].attemptId;
      final r = await c.newPuzzle(page.slots[0]);
      expect(r, NewPuzzleOutcome.replaced);
      final now0 = c.sessionFor(page.slots[0])!;
      expect(now0.def.id, isNot(firstId));
      expect(now0.def.type, page.slots[0].type);
      expect(page.slots[0].history, contains(oldAttempt));
      expect(c.sessionFor(page.slots[1])!.toJson().toString(), otherJson);
      final prev = await c.previousAttempts(page.slots[0]);
      expect(prev.single.puzzleId, firstId);
      expect(prev.single.archived, isTrue);
      c.dispose();
    },
  );

  test('sıfırla: aynı bulmaca, yeni deneme kimliği, temiz durum', () async {
    final c = await open();
    final slot = c.issue!.pages[1].slots[0];
    final s = c.sessionFor(slot)!;
    final oldId = s.meta.id;
    final puzzleId = s.def.id;
    s.mutate(() {
      s.word!.selectEntry(0);
      s.word!.inputLetter('A');
      s.word!.hintLetter();
    });
    await c.resetPuzzle(slot);
    final fresh = c.sessionFor(slot)!;
    expect(fresh.meta.id, isNot(oldId));
    expect(fresh.def.id, puzzleId);
    expect(fresh.word!.letters.every((l) => l.isEmpty), isTrue);
    expect(fresh.game.hintCount, 0);
    expect(fresh.elapsedMs, 0);
    c.dispose();
  });

  test(
    'tamamlanma bir kez kaydedilir; yardımlı/yardımsız ayrılır; yeniden açılınca tekrar yazılmaz',
    () async {
      final c = await open();
      final slot = c.issue!.pages[1].slots[0];
      final s = c.sessionFor(slot)!;
      s.activate();
      clock.advance(const Duration(seconds: 90));
      s.mutate(() {
        s.word!.selectEntry(0);
        s.word!.hintLetter();
      });
      solve(_Solver(s));
      expect(s.meta.completed, isTrue);
      expect(s.justCompleted, isTrue);
      expect(c.completions.length, 1);
      expect(c.completions.single.assisted, isTrue);
      expect(c.completions.single.elapsedMs, 90000);
      // Aynı olayı tekrar tetiklemeye çalış.
      c.completed(s);
      s.mutate(() {});
      expect(c.completions.length, 1);
      final c2 = await restart(c);
      expect(c2.completions.length, 1);
      final s2 = c2.sessionFor(c2.issue!.pages[1].slots[0])!;
      expect(s2.meta.completed, isTrue);
      s2.mutate(() {});
      expect(c2.completions.length, 1);
      c2.dispose();
    },
  );

  test('tamamlanınca süre durur', () async {
    final c = await open();
    final s = c.sessionFor(c.issue!.pages[1].slots[0])!;
    solve(_Solver(s));
    final at = s.elapsedMs;
    clock.advance(const Duration(minutes: 5));
    expect(s.elapsedMs, at);
    c.dispose();
  });

  test('aynı anda yalnızca bir bulmacanın süresi işler', () async {
    final c = await open();
    final a = c.sessionFor(c.issue!.pages[0].slots[0])!;
    final b = c.sessionFor(c.issue!.pages[0].slots[1])!;
    a.activate();
    clock.advance(const Duration(seconds: 10));
    b.activate();
    clock.advance(const Duration(seconds: 20));
    expect(a.elapsedMs, 10000);
    expect(b.elapsedMs, 20000);
    expect(a.timer.running, isFalse);
    c.pauseAll();
    clock.advance(const Duration(minutes: 3));
    expect(b.elapsedMs, 20000, reason: 'menü/arka plan süreyi artırmaz');
    c.dispose();
  });

  test(
    'yeni bulmaca: içerik tükenince açıkça bildirilir, mevcut bulmaca değişmez',
    () async {
      final full = loadLibraryFromDisk();
      // Her türden yalnızca 1 bulmaca → kelime türlerinde yeni içerik yok.
      final one = <PuzzleDefinition>[];
      for (final t in PuzzleType.values) {
        one.add(full.ofType(t).first);
      }
      final c = await open(lib: ContentLibrary(one, const []));
      final slot = c.issue!.pages[1].slots[0];
      final before = c.sessionFor(slot)!;
      final id = before.meta.id;
      final r = await c.newPuzzle(slot);
      expect(r, NewPuzzleOutcome.exhausted);
      expect(slot.attemptId, id);
      expect(c.sessionFor(slot), same(before));
      expect(slot.history, isEmpty);
      c.dispose();
    },
  );

  test(
    'sudoku havuzu tükenince yerel üretim devreye girer ve doğrulanır',
    () async {
      final full = loadLibraryFromDisk();
      final lib = ContentLibrary([
        for (final t in [PuzzleType.cengel, PuzzleType.kare, PuzzleType.klasik])
          ...full.ofType(t),
        full.ofType(PuzzleType.sudoku).first,
      ], const []);
      final c = await open(lib: lib);
      final slot = c.issue!.slots.firstWhere(
        (s) => s.type == PuzzleType.sudoku,
      );
      final oldDef = c.sessionFor(slot)!.def.id;
      final r = await c.newPuzzle(slot);
      expect(r, NewPuzzleOutcome.replaced);
      final s = c.sessionFor(slot)!;
      expect(s.def.id, isNot(oldDef));
      expect(s.def.id, startsWith('sudoku-yerel'));
      c.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'gün değişir: eski ilerleme kaybolmaz, kullanıcı zorla taşınmaz',
    () async {
      final c = await open();
      final s = c.sessionFor(c.issue!.pages[1].slots[0])!;
      s.mutate(() {
        s.word!.selectEntry(0);
        s.word!.inputLetter('A');
      });
      final oldIssue = c.issue!.id;
      await c.onBackground();
      c.dispose();
      now = DateTime(2026, 10, 31, 8);
      final c2 = await open();
      expect(c2.issue!.id, oldIssue, reason: 'yarım kalan sayı korunur');
      expect(c2.newerIssueId, '2026-10-31');
      await c2.openIssue('2026-10-31', createIfMissing: true);
      expect(c2.issue!.id, '2026-10-31');
      await c2.openIssue(oldIssue);
      expect(
        c2.sessionFor(c2.issue!.pages[1].slots[0])!.word!.letters.contains('A'),
        isTrue,
      );
      c2.dispose();
    },
  );

  test('ilerleme yoksa yeni gün doğrudan yeni sayıyla açılır', () async {
    final c = await open();
    await c.onBackground();
    c.dispose();
    now = DateTime(2026, 11, 1, 8);
    final c2 = await open();
    expect(c2.issue!.id, '2026-11-01');
    expect(c2.issue!.number, isNot(c.issue!.number));
    c2.dispose();
  });

  test(
    'bozuk deneme kaydı yalnızca o yuvayı etkiler; dosya karantinaya alınır',
    () async {
      final c = await open();
      final slot = c.issue!.pages[0].slots[0];
      final bad = slot.attemptId;
      await c.onBackground();
      c.dispose();
      await File('${dir.path}/attempts/$bad.json').writeAsString('{kırık json');
      final c2 = await open();
      expect(c2.fatalError, isNull);
      expect(c2.problems.containsKey(slot.id), isTrue);
      expect(c2.sessionFor(c2.issue!.pages[0].slots[1]), isNotNull);
      expect(await c2.store.quarantined(), isNotEmpty);
      expect(File('${dir.path}/attempts/$bad.json').existsSync(), isFalse);
      // Onaylı kurtarma: yuva yeni bulmaca alır, uygulama çalışır.
      await c2.recoverSlot(c2.issue!.pages[0].slots[0]);
      expect(c2.problems, isEmpty);
      expect(c2.sessionFor(c2.issue!.pages[0].slots[0]), isNotNull);
      c2.dispose();
    },
  );

  test(
    'mantıksal olarak bozuk durum (yanlış uzunluk) da izole edilir',
    () async {
      final c = await open();
      final slot = c.issue!.pages[1].slots[0];
      final id = slot.attemptId;
      await c.onBackground();
      c.dispose();
      final f = File('${dir.path}/attempts/$id.json');
      var text = f.readAsStringSync();
      text = text.replaceFirst(
        RegExp(r'"letters":\[[^\]]*\]'),
        '"letters":["A"]',
      );
      f.writeAsStringSync(text);
      final c2 = await open();
      expect(c2.problems.containsKey(slot.id), isTrue);
      c2.dispose();
    },
  );

  test('bozuk ayar dosyası uygulamayı engellemez', () async {
    await dir.create(recursive: true);
    File('${dir.path}/settings.json').writeAsStringSync('###');
    final c = await open();
    expect(c.fatalError, isNull);
    expect(c.notices.join(), contains('Ayar'));
    c.dispose();
  });

  test('kayıt hatası gizlenmez; yeniden deneme çalışır', () async {
    final c = await open();
    await c.store.flush();
    // attempts klasörünü dosyayla değiştirerek yazmayı imkânsız kıl.
    final attempts = Directory('${dir.path}/attempts');
    attempts.deleteSync(recursive: true);
    File('${dir.path}/attempts').writeAsStringSync('engel');
    final s = c.sessionFor(c.issue!.pages[1].slots[0])!;
    s.mutate(() {
      s.word!.selectEntry(0);
      s.word!.inputLetter('A');
    });
    await c.store.flush();
    expect(c.store.saveError.value, isNotNull);
    // Engeli kaldır ve tekrar dene.
    File('${dir.path}/attempts').deleteSync();
    Directory('${dir.path}/attempts').createSync();
    expect(await c.store.retry(), isTrue);
    expect(c.store.saveError.value, isNull);
    final c2 = await restart(c);
    final s2 = c2.sessionFor(c2.issue!.pages[1].slots[0])!;
    expect(
      s2.word!.letters.contains('A'),
      isTrue,
      reason: 'başarısız yazma bekletildi ve sonra diske indi',
    );
    c2.dispose();
  });

  test('hızlı art arda yazmada eski durum yenisini ezmez', () async {
    final c = await open();
    final s = c.sessionFor(c.issue!.pages[1].slots[0])!;
    s.word!.selectEntry(0);
    final cells = s.word!.activeCells;
    for (var i = 0; i < cells.length; i++) {
      s.mutate(() => s.word!.inputLetter('ABCDEFGHIJ'[i % 10]));
    }
    final expected = List<String>.from(s.word!.letters);
    final c2 = await restart(c);
    final s2 = c2.sessionFor(c2.issue!.pages[1].slots[0])!;
    expect(s2.word!.letters, expected);
    c2.dispose();
  });

  test('içerik güncellenirse açık deneme eski sürümle devam eder', () async {
    final c = await open();
    final s = c.sessionFor(c.issue!.pages[1].slots[0])!;
    final id = s.def.id;
    await c.onBackground();
    c.dispose();
    // Havuzdan aynı kimliği farklı sürümle ve farklı içerikle yayımla.
    final lib = loadLibraryFromDisk();
    final v1 = lib.byId(id)!;
    final updated = ContentLibrary([
      for (final p in lib.puzzles)
        if (p.id != id) p,
      PuzzleDefinition(
        id: v1.id,
        version: 2,
        type: v1.type,
        difficulty: v1.difficulty,
        title: 'Yeni sürüm',
        source: v1.source,
        license: v1.license,
        rows: v1.rows,
        cols: v1.cols,
        grid: v1.grid,
        entries: v1.entries,
      ),
    ], const []);
    final c2 = await open(lib: updated);
    final s2 = c2.sessionFor(c2.issue!.pages[1].slots[0])!;
    expect(s2.def.version, 1);
    expect(s2.def.title, v1.title);
    c2.dispose();
  });

  test(
    'aynı yuvada eşzamanlı "yeni bulmaca" çakışmaz: biri uygulanır, öteki beklemeyi bildirir',
    () async {
      final c = await open();
      final slot = c.issue!.pages[0].slots[0];
      final results = await Future.wait([c.newPuzzle(slot), c.newPuzzle(slot)]);
      expect(results.where((r) => r == NewPuzzleOutcome.replaced).length, 1);
      expect(results.where((r) => r == NewPuzzleOutcome.busy).length, 1);
      expect(
        slot.history.length,
        1,
        reason: 'eski deneme yalnızca bir kez arşivlenir',
      );
      expect(c.sessionFor(slot), isNotNull);
      expect(c.issue!.slots.every((s) => c.sessionFor(s) != null), isTrue);
      c.dispose();
    },
  );

  test('aynı yuvada eşzamanlı sıfırla ikinci kez uygulanmaz', () async {
    final c = await open();
    final slot = c.issue!.pages[1].slots[0];
    final before = slot.attemptId;
    await Future.wait([c.resetPuzzle(slot), c.resetPuzzle(slot)]);
    expect(slot.attemptId, isNot(before));
    expect(c.sessionFor(slot), isNotNull);
    c.dispose();
  });

  test('yeni güne geçince önceki sayının sayfa indeksi taşınmaz', () async {
    final c = await open();
    c.setLastPage(3);
    await c.onBackground();
    c.dispose();
    now = DateTime(2026, 11, 2, 8);
    final c2 = await open();
    expect(c2.issue!.id, '2026-11-02');
    expect(c2.settings.lastPage, 0);
    c2.dispose();
  });

  test(
    'sayı numarası: kurulum günü 1, sonraki her gün +1 (telefon tarihine göre)',
    () async {
      final c = await open();
      expect(c.issue!.number, 1, reason: 'ilk açılış günü 1. sayı');
      expect(c.settings.firstLaunchDate, '2026-10-30');
      await c.onBackground();
      c.dispose();

      now = DateTime(2026, 10, 31, 9);
      var c2 = await open();
      await c2.openIssue('2026-10-31', createIfMissing: true);
      expect(c2.issue!.number, 2);
      await c2.onBackground();
      c2.dispose();

      // Birkaç gün sonra (ay sınırı dahil) numara takvim gününe göre artar.
      now = DateTime(2026, 11, 8, 9);
      c2 = await open();
      await c2.openIssue('2026-11-08', createIfMissing: true);
      expect(c2.issue!.number, 10);
      // Eski sayıların numaraları değişmez.
      await c2.openIssue('2026-10-30');
      expect(c2.issue!.number, 1);
      c2.dispose();
    },
  );

  test('aynı gün birden çok açılış numarayı değiştirmez', () async {
    final c = await open();
    final n = c.issue!.number;
    final c2 = await restart(c);
    expect(c2.issue!.number, n);
    expect(c2.settings.firstLaunchDate, '2026-10-30');
    c2.dispose();
  });

  test(
    'telefon saati kurulum gününden önceye alınırsa numara 1\'in altına inmez',
    () async {
      final c = await open();
      await c.onBackground();
      c.dispose();
      now = DateTime(2026, 10, 20, 9);
      final c2 = await open();
      await c2.openIssue('2026-10-20', createIfMissing: true);
      expect(c2.issue!.number, 1);
      c2.dispose();
    },
  );

  test('ayar dosyası kaybolsa da numaralama en eski sayıdan sürer', () async {
    final c = await open();
    await c.onBackground();
    c.dispose();
    File('${dir.path}/settings.json').deleteSync();
    now = DateTime(2026, 11, 2, 9); // 4. gün
    final c2 = await open();
    expect(c2.settings.firstLaunchDate, '2026-10-30');
    await c2.openIssue('2026-11-02', createIfMissing: true);
    expect(c2.issue!.number, 4);
    c2.dispose();
  });

  test('yeni gün sayısı otomatik açılırsa doğru numarayı taşır', () async {
    final c = await open();
    await c.onBackground();
    c.dispose();
    now = DateTime(2026, 11, 3, 8); // 5. gün, ilerleme yok → doğrudan yeni sayı
    final c2 = await open();
    expect(c2.issue!.id, '2026-11-03');
    expect(c2.issue!.number, 5);
    c2.dispose();
  });

  test('arşiv özeti durum ve türleri doğru verir', () async {
    final c = await open();
    final s = c.sessionFor(c.issue!.pages[1].slots[0])!;
    solve(_Solver(s));
    final other = c.sessionFor(c.issue!.pages[0].slots[0])!;
    other.mutate(() {
      other.word?.selectEntry(0);
      other.word?.inputLetter('A');
    });
    await c.store.flush();
    final sum = await c.summarize(c.issue!.id);
    expect(sum!.completed, 1);
    expect(sum.inProgress, 1);
    expect(sum.total, 8);
    expect(sum.types, isNotEmpty);
    expect(await c.issueIds(), contains(c.issue!.id));
    c.dispose();
  });
}
