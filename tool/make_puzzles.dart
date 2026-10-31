// İçerik üretim hattı (geliştirici aracı; uygulama içinde çalışmaz).
//
//   dart run tool/make_puzzles.dart
//
// Özgün kelime bankasından (tool/word_bank.dart) kesişimleri tutan kelime
// bulmacaları kurar ve her birini ContentValidator'dan geçirir. Doğrulamayı
// geçemeyen bulmaca ASLA yazılmaz. Sudoku'lar tek çözüm ve mantıksal zorluk
// için doğrulanır. Çıktı: assets/puzzles/*.json
//
// Not: Bu bir "sınırsız bulmaca" üreteci değildir. Kelime bulmacası kalitesi
// banka ve ipucu editörlüğüne bağlıdır; ürettiklerimiz yalnızca bankadaki
// özgün ipuçlarını kullanır.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bulmaca_postasi/core/turkish.dart';
import 'package:bulmaca_postasi/domain/puzzle.dart';
import 'package:bulmaca_postasi/domain/sudoku_generator.dart';
import 'package:bulmaca_postasi/domain/validator.dart';
import 'package:bulmaca_postasi/domain/word_structure.dart';

import 'bank_all.dart';
import 'word_bank.dart';

const _source = 'Özgün içerik — Bulmaca Gazetesi geliştirici bankası';
const _license =
    'Proje içi özgün içerik (telif devri yok, üçüncü taraf içeriği yok)';

class _Placed {
  _Placed(this.word, this.dir, this.r, this.c);
  final Word word;
  final Dir dir;
  final int r, c;
}

class _Builder {
  _Builder(this.rows, this.cols, this.cengel, this.rng)
    : g = List.generate(rows, (_) => List<String?>.filled(cols, null)),
      blk = List.generate(rows, (_) => List<bool>.filled(cols, false)),
      cover = List.generate(rows, (_) => List<int>.filled(cols, 0));

  final int rows, cols;
  final bool cengel;
  final Random rng;
  final List<List<String?>> g;
  final List<List<bool>> blk;
  final List<List<int>> cover;
  final Map<int, int> clueDirs = {};
  final List<_Placed> placed = [];

  int bitOf(Dir d) => d == Dir.across ? 1 : 2;
  bool inb(int r, int c) => r >= 0 && c >= 0 && r < rows && c < cols;

  /// Yerleştirilebiliyorsa kesişim sayısı, değilse null.
  int? score(Word w, Dir dir, int r, int c) {
    final l = Turkish.letters(w.$1);
    final n = l.length;
    final dr = dir.dr, dc = dir.dc;
    final br = r - dr, bc = c - dc, ar = r + dr * n, ac = c + dc * n;
    if (!inb(r + dr * (n - 1), c + dc * (n - 1)) || !inb(r, c)) return null;
    if (cengel && !inb(br, bc)) return null;
    if (inb(br, bc)) {
      if (g[br][bc] != null) return null;
      if (cengel && (clueDirs[br * cols + bc] ?? 0) & bitOf(dir) != 0) {
        return null;
      }
    }
    if (inb(ar, ac) && g[ar][ac] != null) return null;
    var cross = 0;
    for (var i = 0; i < n; i++) {
      final rr = r + dr * i, cc = c + dc * i;
      if (blk[rr][cc]) return null;
      final ex = g[rr][cc];
      if (ex != null) {
        if (ex != l[i] || cover[rr][cc] & bitOf(dir) != 0) return null;
        cross++;
      } else {
        for (final s in const [-1, 1]) {
          final nr = rr + dc * s, nc = cc + dr * s;
          if (inb(nr, nc) && g[nr][nc] != null) return null;
        }
      }
    }
    return cross;
  }

  void place(Word w, Dir dir, int r, int c) {
    final l = Turkish.letters(w.$1);
    for (var i = 0; i < l.length; i++) {
      final rr = r + dir.dr * i, cc = c + dir.dc * i;
      g[rr][cc] = l[i];
      cover[rr][cc] |= bitOf(dir);
    }
    final br = r - dir.dr, bc = c - dir.dc;
    final ar = r + dir.dr * l.length, ac = c + dir.dc * l.length;
    if (inb(br, bc)) {
      blk[br][bc] = true;
      if (cengel) {
        clueDirs[br * cols + bc] = (clueDirs[br * cols + bc] ?? 0) | bitOf(dir);
      }
    }
    if (inb(ar, ac)) blk[ar][ac] = true;
    placed.add(_Placed(w, dir, r, c));
  }

  int get letterCount {
    var n = 0;
    for (final row in g) {
      for (final v in row) {
        if (v != null) n++;
      }
    }
    return n;
  }
}

_Builder? _build({
  required int rows,
  required int cols,
  required bool cengel,
  required List<Word> pool,
  required int target,
  required int seed,
}) {
  final rng = Random(seed);
  final b = _Builder(rows, cols, cengel, rng);
  final words = List<Word>.from(pool)..shuffle(rng);
  // İlk kelime: uzun bir kelime, ortaya yakın.
  final firsts = words.where((w) => Turkish.letterCount(w.$1) >= 6).toList();
  final first = firsts.isEmpty
      ? words.first
      : firsts[rng.nextInt(firsts.length)];
  var ok = false;
  for (var t = 0; t < 200 && !ok; t++) {
    final dir = rng.nextBool() ? Dir.across : Dir.down;
    final r = 1 + rng.nextInt(max(1, rows ~/ 2));
    final c = 1 + rng.nextInt(max(1, cols ~/ 2));
    if (b.score(first, dir, r, c) != null) {
      b.place(first, dir, r, c);
      ok = true;
    }
  }
  if (!ok) return null;
  final used = <String>{first.$1};
  while (b.placed.length < target) {
    final cands = <(Word, Dir, int, int, int)>[];
    final sample = words.where((w) => !used.contains(w.$1)).take(220);
    for (final w in sample) {
      final l = Turkish.letters(w.$1);
      for (final dir in Dir.values) {
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            final ch = b.g[r][c];
            if (ch == null) continue;
            for (var i = 0; i < l.length; i++) {
              if (l[i] != ch) continue;
              final sr = r - dir.dr * i, sc = c - dir.dc * i;
              final s = b.score(w, dir, sr, sc);
              if (s != null && s >= 1) cands.add((w, dir, sr, sc, s));
            }
          }
        }
      }
    }
    if (cands.isEmpty) break;
    final best = cands.map((e) => e.$5).reduce(max);
    final top = cands
        .where((e) => e.$5 >= max(1, best - (rng.nextInt(3) == 0 ? 1 : 0)))
        .toList();
    final pick = top[rng.nextInt(top.length)];
    b.place(pick.$1, pick.$2, pick.$3, pick.$4);
    used.add(pick.$1.$1);
  }
  return b;
}

PuzzleDefinition? _toDefinition(
  _Builder b, {
  required String id,
  required PuzzleType type,
  required Difficulty diff,
  required String title,
}) {
  // Kırpma: harfler (çengelde soru hücreleri de) sınırlayıcı kutuya girer.
  var r0 = b.rows, r1 = -1, c0 = b.cols, c1 = -1;
  void grow(int r, int c) {
    r0 = min(r0, r);
    r1 = max(r1, r);
    c0 = min(c0, c);
    c1 = max(c1, c);
  }

  for (var r = 0; r < b.rows; r++) {
    for (var c = 0; c < b.cols; c++) {
      if (b.g[r][c] != null) grow(r, c);
    }
  }
  if (b.cengel) {
    for (final k in b.clueDirs.keys) {
      grow(k ~/ b.cols, k % b.cols);
    }
  }
  final rows = r1 - r0 + 1, cols = c1 - c0 + 1;
  final grid = [
    for (var r = r0; r <= r1; r++)
      [for (var c = c0; c <= c1; c++) b.g[r][c] ?? '#'].join(),
  ];
  bool letter(int r, int c) =>
      r >= 0 && c >= 0 && r < rows && c < cols && grid[r][c] != '#';
  final nums = b.cengel
      ? const <int, int>{}
      : WordStructure.numbering(rows, cols, letter);
  final entries = <WordEntry>[];
  final sorted = [...b.placed]
    ..sort((a, z) => a.r != z.r ? a.r - z.r : a.c - z.c);
  var k = 0;
  for (final p in sorted) {
    final r = p.r - r0, c = p.c - c0;
    k++;
    if (b.cengel) {
      entries.add(
        WordEntry(
          id: 'e$k',
          dir: p.dir,
          row: r,
          col: c,
          answer: p.word.$1,
          clue: p.word.$2,
          clueRow: r - p.dir.dr,
          clueCol: c - p.dir.dc,
          category: p.word.$3,
        ),
      );
    } else {
      final n = nums[r * cols + c]!;
      entries.add(
        WordEntry(
          id: '${p.dir.key}$n',
          dir: p.dir,
          row: r,
          col: c,
          number: n,
          answer: p.word.$1,
          clue: p.word.$2,
          category: p.word.$3,
        ),
      );
    }
  }
  final def = PuzzleDefinition(
    id: id,
    version: 1,
    type: type,
    difficulty: diff,
    title: title,
    source: _source,
    license: _license,
    rows: rows,
    cols: cols,
    grid: grid,
    entries: entries,
  );
  final errs = ContentValidator.validate(def);
  if (errs.isNotEmpty) {
    stderr.writeln('  REDDEDİLDİ $id: ${errs.take(3).join(' | ')}');
    return null;
  }
  return def;
}

List<Word> _poolFor(PuzzleType type, Difficulty diff) {
  final minLen = type == PuzzleType.klasik ? 4 : 3;
  final maxLen = type == PuzzleType.klasik ? 11 : 9;
  final maxClue = type == PuzzleType.cengel
      ? ContentValidator.maxCengelClueChars
      : ContentValidator.maxClueChars;
  final base = allWords.where((w) {
    final n = Turkish.letterCount(w.$1);
    return n >= minLen &&
        n <= maxLen &&
        w.$2.length <= maxClue &&
        Turkish.isValidAnswer(w.$1) &&
        Turkish.upper(w.$1) == w.$1;
  }).toList();
  if (diff == Difficulty.kolay) return base.where((w) => w.$4 == 1).toList();
  // Orta/zor: ikinci seviye kelimeler öne alınır (yine de birinci seviye ile karışır).
  final hard = base.where((w) => w.$4 == 2).toList();
  final easy = base.where((w) => w.$4 == 1).toList()..shuffle(Random(7));
  final easyShare = diff == Difficulty.orta ? 1200 : 900;
  return [...hard, ...hard, ...easy.take(easyShare)];
}

PuzzleDefinition? _makeWord({
  required PuzzleType type,
  required Difficulty diff,
  required int index,
  required int baseSeed,
  required Set<String> usedAnswers,
  Map<String, int>? useCount,
  int cap = 99,
  int? restartsOverride,
  String? idOverride,
  String? titleOverride,
}) {
  final (rows, cols, target, minEntries, restarts0) = switch (type) {
    PuzzleType.cengel => (11, 11, 14, 9, 160),
    PuzzleType.kare => (11, 11, 16, 11, 160),
    _ => (15, 15, 30, 20, 90),
  };
  final restarts = restartsOverride ?? restarts0;
  var pool = _poolFor(type, diff);
  if (useCount != null) {
    // Aynı cevap bir türde en çok [cap] kez; en az kullanılanlar öne alınır.
    final ok = pool.where((w) => (useCount[w.$1] ?? 0) < cap).toList();
    if (ok.isNotEmpty) {
      final low = ok.map((w) => useCount[w.$1] ?? 0).reduce(min);
      final tier = ok.where((w) => (useCount[w.$1] ?? 0) <= low + 1).toList();
      pool = tier.length >= 150 ? tier : ok;
    }
  } else {
    // Önceki bulmacalarda geçen cevapları mümkünse tekrar kullanma.
    final fresh = pool.where((w) => !usedAnswers.contains(w.$1)).toList();
    if (fresh.length > 60) pool = fresh;
  }
  PuzzleDefinition? best;
  var bestScore = -1.0;
  final stat = <String, int>{};
  stat['havuz'] = pool.length;
  for (var s = 0; s < restarts; s++) {
    final b = _build(
      rows: rows,
      cols: cols,
      cengel: type == PuzzleType.cengel,
      pool: pool,
      target: target,
      seed: baseSeed * 1000 + s,
    );
    if (b == null) {
      stat['kurulamadı'] = (stat['kurulamadı'] ?? 0) + 1;
      continue;
    }
    if (b.placed.length < minEntries) {
      stat['az cevap'] = (stat['az cevap'] ?? 0) + 1;
      continue;
    }
    final def = _toDefinition(
      b,
      id:
          idOverride ??
          '${type.key}-${diff.key}-${(index + 1).toString().padLeft(2, '0')}',
      type: type,
      diff: diff,
      title: titleOverride ?? '${type.label} ${_roman(index + 1)}',
    );
    if (def == null) {
      stat['doğrulayıcı reddi'] = (stat['doğrulayıcı reddi'] ?? 0) + 1;
      continue;
    }
    if (type == PuzzleType.klasik &&
        def.entries.map((e) => e.category).toSet().length < 4) {
      stat['az kategori'] = (stat['az kategori'] ?? 0) + 1;
      continue;
    }
    final letters = def.grid.join().replaceAll('#', '').length;
    final sc = letters / (def.rows * def.cols) * 10 + def.entries.length * 0.5;
    if (sc > bestScore) {
      bestScore = sc;
      best = def;
    }
  }
  if (best == null && stat.isNotEmpty) {
    stderr.writeln('  tanı ${diff.key}: $stat');
  }
  if (best != null) usedAnswers.addAll(best.entries.map((e) => e.answer));
  return best;
}

String _roman(int n) {
  const t = [
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  var r = '';
  for (final (v, sym) in t) {
    while (n >= v) {
      r += sym;
      n -= v;
    }
  }
  return r;
}

void _write(String name, List<PuzzleDefinition> list) {
  final f = File('assets/puzzles/$name.json');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(
    const JsonEncoder.withIndent(
      ' ',
    ).convert([for (final p in list) p.toJson()]),
  );
  stdout.writeln('$name.json: ${list.length} bulmaca');
}

/// Toplu üretim: `dart tool/make_puzzles.dart bulk <tür> [hedef=100]`.
/// Mevcut bulmacalara (kimlik/içerik) dokunmaz; eksik kalan sayıyı
/// `assets/puzzles/<tür>_bulk.json` dosyasına yeni kimliklerle ekler.
Future<void> bulk(String typeKey, int total) async {
  final type = PuzzleType.parse(typeKey);
  final oldFile = File('assets/puzzles/$typeKey.json');
  final old = oldFile.existsSync()
      ? [
          for (final j in jsonDecode(oldFile.readAsStringSync()) as List)
            PuzzleDefinition.fromJson(j as Map<String, dynamic>),
        ]
      : <PuzzleDefinition>[];
  // Yarım kalan toplu üretimi sürdür: mevcut `_bulk` dosyası korunur.
  final bulkFile = File('assets/puzzles/${typeKey}_bulk.json');
  final resumed = bulkFile.existsSync()
      ? [
          for (final j in jsonDecode(bulkFile.readAsStringSync()) as List)
            PuzzleDefinition.fromJson(j as Map<String, dynamic>),
        ]
      : <PuzzleDefinition>[];
  final base = old.length;
  old.addAll(resumed);
  final want = type == PuzzleType.sudoku
      ? {Difficulty.kolay: 34, Difficulty.orta: 33, Difficulty.zor: 33}
      : {Difficulty.kolay: 40, Difficulty.orta: 35, Difficulty.zor: 25};
  final scale = total / 100;
  final need = <Difficulty>[];
  for (final d in Difficulty.values) {
    final have = old.where((p) => p.difficulty == d).length;
    for (var i = 0; i < (want[d]! * scale).round() - have; i++) {
      need.add(d);
    }
  }
  need.shuffle(Random(7 + type.index));
  final useCount = <String, int>{};
  for (final p in old) {
    for (final e in p.entries) {
      useCount[e.answer] = (useCount[e.answer] ?? 0) + 1;
    }
  }
  final poolSize =
      _poolFor(type, Difficulty.zor).length +
      _poolFor(type, Difficulty.kolay).length;
  final avgEntries = switch (type) {
    PuzzleType.cengel => 14,
    PuzzleType.kare => 16,
    _ => 27,
  };
  final cap = max(
    type == PuzzleType.klasik ? 7 : 4,
    (need.length * avgEntries / (poolSize * 0.6) * 3.0).ceil(),
  );
  stdout.writeln(
    '$typeKey: ${old.length} mevcut, ${need.length} üretilecek, '
    'cevap tekrar sınırı=$cap, havuz≈$poolSize',
  );

  final out = <PuzzleDefinition>[...resumed];
  final existingGivens = {for (final p in old) p.givens};
  var failures = 0;
  var n = old.length;
  stdout.writeln(
    '$typeKey: ${resumed.length} yarım kalan bulmaca sürdürülüyor',
  );
  for (final d in need) {
    n++;
    final num3 = n.toString().padLeft(3, '0');
    PuzzleDefinition? p;
    if (type == PuzzleType.sudoku) {
      for (var k = 0; k < 40 && p == null; k++) {
        final g = generateSudoku(d, 100000 + n * 97 + k * 13 + d.index);
        if (g == null || existingGivens.contains(g.givens)) continue;
        existingGivens.add(g.givens);
        p = PuzzleDefinition(
          id: 'sudoku-${d.key}-$num3',
          version: 1,
          type: type,
          difficulty: g.difficulty,
          title: 'Sudoku ${_roman(n)}',
          source: 'Yerel üretim (tool/make_puzzles.dart); tek çözüm doğrulandı',
          license: _license,
          rows: 9,
          cols: 9,
          givens: g.givens,
          solution: g.solution,
        );
        if (ContentValidator.validate(p).isNotEmpty) p = null;
      }
    } else {
      for (var attempt = 0; attempt < 5 && p == null; attempt++) {
        p = _makeWord(
          type: type,
          diff: d,
          index: n - 1,
          baseSeed: 5000 + n * 7 + attempt * 1013 + type.index * 100003,
          usedAnswers: <String>{},
          useCount: useCount,
          cap: cap,
          restartsOverride: type == PuzzleType.klasik ? 110 : 70,
          idOverride: '${type.key}-${d.key}-$num3',
          titleOverride: '${type.label} ${_roman(n)}',
        );
      }
      if (p != null) {
        for (final e in p.entries) {
          useCount[e.answer] = (useCount[e.answer] ?? 0) + 1;
        }
      }
    }
    if (p == null) {
      failures++;
      stderr.writeln('BAŞARISIZ: $typeKey $n (${d.key})');
      n--;
      continue;
    }
    out.add(p);
    if (out.length % 5 == 0) {
      _write('${typeKey}_bulk', out);
      stdout.writeln('  ${base + out.length}/$total');
    }
  }
  _write('${typeKey}_bulk', out);
  stdout.writeln(
    '$typeKey: toplam ${old.length + out.length} (başarısız: $failures)',
  );
  if (failures > 0) exit(1);
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'bulk') {
    await bulk(args[1], args.length > 2 ? int.parse(args[2]) : 100);
    return;
  }
  if (!args.contains('--seed-set')) {
    stderr.writeln(
      'Kullanım:\n'
      '  dart tool/make_puzzles.dart bulk <cengel|kare|klasik|sudoku> [hedef]\n'
      '  dart tool/make_puzzles.dart --seed-set   (ilk 36 bulmacayı YENİDEN üretir; '
      'kayıtlı denemeleri bozabilir, kullanmayın)',
    );
    exit(64);
  }
  // Banka sağlık denetimi.
  final seen = <String>{};
  for (final w in wordBank) {
    if (!seen.add(w.$1)) {
      stderr.writeln('UYARI: bankada yinelenen cevap ${w.$1}');
    }
  }
  const plan = {
    PuzzleType.cengel: [
      Difficulty.kolay,
      Difficulty.kolay,
      Difficulty.orta,
      Difficulty.zor,
    ],
    PuzzleType.kare: [
      Difficulty.kolay,
      Difficulty.kolay,
      Difficulty.orta,
      Difficulty.zor,
    ],
    PuzzleType.klasik: [
      Difficulty.kolay,
      Difficulty.orta,
      Difficulty.orta,
      Difficulty.zor,
    ],
  };
  var failures = 0;
  for (final entry in plan.entries) {
    final used = <String>{};
    final out = <PuzzleDefinition>[];
    for (var i = 0; i < entry.value.length; i++) {
      final d = entry.value[i];
      final p = _makeWord(
        type: entry.key,
        diff: d,
        index: i,
        baseSeed: 11 + i * 7 + entry.key.index * 101,
        usedAnswers: used,
      );
      if (p == null) {
        stderr.writeln('BAŞARISIZ: ${entry.key.key} #$i (${d.key})');
        failures++;
      } else {
        stdout.writeln(
          '  ${p.id}: ${p.rows}x${p.cols}, ${p.entries.length} cevap',
        );
        out.add(p);
      }
    }
    _write(entry.key.key, out);
  }

  // Sudoku: sabit tohumlar; tek çözüm ve zorluk üretici içinde doğrulanır.
  final sud = <PuzzleDefinition>[];
  for (final d in Difficulty.values) {
    var made = 0;
    for (var seed = 1; made < 8 && seed < 400; seed++) {
      final g = generateSudoku(d, seed * 31 + d.index);
      if (g == null) continue;
      made++;
      sud.add(
        PuzzleDefinition(
          id: 'sudoku-${d.key}-${made.toString().padLeft(2, '0')}',
          version: 1,
          type: PuzzleType.sudoku,
          difficulty: d,
          title: 'Sudoku ${_roman(made)}',
          source: 'Yerel üretim (tool/make_puzzles.dart); tek çözüm doğrulandı',
          license: _license,
          rows: 9,
          cols: 9,
          givens: g.givens,
          solution: g.solution,
        ),
      );
    }
    stdout.writeln('sudoku ${d.key}: $made');
  }
  final pool = [...sud];
  final errs = ContentValidator.validatePool(pool);
  if (errs.isNotEmpty) {
    stderr.writeln('Sudoku havuz hataları: ${errs.take(5)}');
    failures++;
  }
  _write('sudoku', sud);
  if (failures > 0) {
    stderr.writeln('$failures üretim hatası var — içerik eksik!');
    exit(1);
  }
}
