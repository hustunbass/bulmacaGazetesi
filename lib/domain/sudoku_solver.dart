import 'dart:math';

import 'puzzle.dart';

/// Sudoku çözücü, tek çözüm denetleyicisi ve mantıksal zorluk derecelendirici.
///
/// Zorluk derecelendirmesi yalnızca başlangıç sayısına bakmaz; çözümün hangi
/// tekniklerle bulunabildiğine dayanır:
///  * kolay: yalnızca "tek aday" (naked single) ile çözülür.
///  * orta: "tek aday" + "tek yer" (hidden single) ile çözülür.
///  * zor: tek çözümlüdür ama bu iki teknik yetmez (ileri teknik veya deneme
///    gerekir). Zor sınıfı bu nedenle geniş bir aralığı kapsar; "zor"un üst
///    sınırı ölçülmez.
class SudokuSolver {
  SudokuSolver._();

  static const full = 0x1FF;

  static final List<List<int>> peers = List.generate(81, (i) {
    final r = i ~/ 9, c = i % 9;
    final s = <int>{};
    for (var k = 0; k < 9; k++) {
      s.add(r * 9 + k);
      s.add(k * 9 + c);
    }
    final br = r ~/ 3 * 3, bc = c ~/ 3 * 3;
    for (var a = 0; a < 3; a++) {
      for (var b = 0; b < 3; b++) {
        s.add((br + a) * 9 + bc + b);
      }
    }
    s.remove(i);
    return s.toList();
  });

  /// 27 ev: 9 satır, 9 sütun, 9 bölge.
  static final List<List<int>> houses = [
    for (var r = 0; r < 9; r++) [for (var c = 0; c < 9; c++) r * 9 + c],
    for (var c = 0; c < 9; c++) [for (var r = 0; r < 9; r++) r * 9 + c],
    for (var b = 0; b < 9; b++)
      [
        for (var k = 0; k < 9; k++)
          (b ~/ 3 * 3 + k ~/ 3) * 9 + (b % 3 * 3 + k % 3),
      ],
  ];

  static List<int> parse(String s) {
    if (s.length != 81) throw ContentException('Sudoku 81 karakter olmalı');
    return [
      for (final ch in s.split(''))
        switch (ch) {
          '.' || '0' => 0,
          _ => int.tryParse(ch)?.clamp(0, 9) ?? 0,
        },
    ];
  }

  static String encode(List<int> g) => g.join();

  static int bit(int d) => 1 << (d - 1);

  /// Başlangıç ızgarasında kural çakışması var mı.
  static bool hasConflict(List<int> g) => conflicts(g).isNotEmpty;

  /// Aynı satır/sütun/bölgede tekrar eden değerleri taşıyan hücreler.
  static Set<int> conflicts(List<int> g) {
    final bad = <int>{};
    for (final h in houses) {
      final seen = <int, int>{};
      for (final i in h) {
        final v = g[i];
        if (v == 0) continue;
        final other = seen[v];
        if (other != null) {
          bad
            ..add(i)
            ..add(other);
        } else {
          seen[v] = i;
        }
      }
    }
    return bad;
  }

  static List<int> candidates(List<int> g) {
    final cand = List<int>.filled(81, 0);
    for (var i = 0; i < 81; i++) {
      if (g[i] != 0) continue;
      var m = full;
      for (final p in peers[i]) {
        if (g[p] != 0) m &= ~bit(g[p]);
      }
      cand[i] = m;
    }
    return cand;
  }

  static int _popcount(int x) {
    var n = 0;
    while (x != 0) {
      x &= x - 1;
      n++;
    }
    return n;
  }

  /// Çözüm sayısını [limit]'e kadar sayar. Bütçe aşılırsa `exhausted` true olur
  /// ve sayı güvenilmez kabul edilmelidir.
  static ({int count, bool exhausted, List<int>? first}) countSolutions(
    List<int> start, {
    int limit = 2,
    int maxNodes = 400000,
  }) {
    final g = List<int>.from(start);
    if (hasConflict(g)) return (count: 0, exhausted: false, first: null);
    var count = 0;
    var nodes = 0;
    var exhausted = false;
    List<int>? first;

    void search() {
      if (count >= limit || exhausted) return;
      if (++nodes > maxNodes) {
        exhausted = true;
        return;
      }
      final cand = candidates(g);
      var best = -1, bestN = 10;
      for (var i = 0; i < 81; i++) {
        if (g[i] != 0) continue;
        final n = _popcount(cand[i]);
        if (n == 0) return;
        if (n < bestN) {
          bestN = n;
          best = i;
          if (n == 1) break;
        }
      }
      if (best < 0) {
        count++;
        first ??= List<int>.from(g);
        return;
      }
      for (var d = 1; d <= 9; d++) {
        if (cand[best] & bit(d) == 0) continue;
        g[best] = d;
        search();
        g[best] = 0;
        if (count >= limit || exhausted) return;
      }
    }

    search();
    return (count: count, exhausted: exhausted, first: first);
  }

  /// Yalnızca tek aday (ve istenirse tek yer) ile çözülebiliyor mu.
  static bool solvableBySingles(List<int> start, {required bool hidden}) {
    final g = List<int>.from(start);
    var progress = true;
    while (progress) {
      progress = false;
      final cand = candidates(g);
      for (var i = 0; i < 81; i++) {
        if (g[i] == 0 && cand[i] != 0 && _popcount(cand[i]) == 1) {
          g[i] = _digitOf(cand[i]);
          progress = true;
          break;
        }
        if (g[i] == 0 && cand[i] == 0) return false;
      }
      if (progress) continue;
      if (hidden) {
        outer:
        for (final h in houses) {
          for (var d = 1; d <= 9; d++) {
            int? only;
            var n = 0;
            for (final i in h) {
              if (g[i] == d) {
                n = 99;
                break;
              }
              if (g[i] == 0 && cand[i] & bit(d) != 0) {
                n++;
                only = i;
              }
            }
            if (n == 1) {
              g[only!] = d;
              progress = true;
              break outer;
            }
          }
        }
      }
    }
    return !g.contains(0);
  }

  static int _digitOf(int mask) {
    for (var d = 1; d <= 9; d++) {
      if (mask == bit(d)) return d;
    }
    return 0;
  }

  /// Tek çözümlü bir bulmaca için mantıksal zorluk.
  static Difficulty rate(List<int> g) {
    if (solvableBySingles(g, hidden: false)) return Difficulty.kolay;
    if (solvableBySingles(g, hidden: true)) return Difficulty.orta;
    return Difficulty.zor;
  }

  /// Rastgele geçerli tam çözüm.
  static List<int> randomSolution(Random rng) {
    final g = List<int>.filled(81, 0);
    bool fill(int i) {
      if (i == 81) return true;
      final cand = candidates(g)[i];
      final digits = [
        for (var d = 1; d <= 9; d++)
          if (cand & bit(d) != 0) d,
      ]..shuffle(rng);
      for (final d in digits) {
        g[i] = d;
        if (fill(i + 1)) return true;
      }
      g[i] = 0;
      return false;
    }

    fill(0);
    return g;
  }
}

/// Seçili hücre için gerçekten tespit edilmiş bir mantıksal açıklama.
class SudokuHintExplanation {
  const SudokuHintExplanation(this.digit, this.text);
  final int digit;
  final String text;
}

class SudokuLogic {
  SudokuLogic._();

  /// Yalnızca tek aday veya tek yer tekniği gerçekten uygulanabiliyorsa
  /// açıklama döndürür; aksi halde null (arayüz "Hücreyi aç" önerir).
  static SudokuHintExplanation? explain(
    List<int> g,
    int idx,
    int solutionDigit,
  ) {
    if (g[idx] != 0 || SudokuSolver.hasConflict(g)) return null;
    final cand = SudokuSolver.candidates(g);
    final mask = cand[idx];
    if (mask == SudokuSolver.bit(solutionDigit)) {
      return SudokuHintExplanation(
        solutionDigit,
        'Bu hücrenin satırında, sütununda ve 3×3 bölgesinde diğer rakamlar '
        'zaten var. Geriye yalnızca $solutionDigit kalıyor.',
      );
    }
    const names = ['satırda', 'sütunda', '3×3 bölgede'];
    final r = idx ~/ 9, c = idx % 9;
    final houseIdx = [r, 9 + c, 18 + (r ~/ 3 * 3 + c ~/ 3)];
    for (var k = 0; k < 3; k++) {
      final h = SudokuSolver.houses[houseIdx[k]];
      if (h.any((i) => g[i] == solutionDigit)) continue;
      final spots = [
        for (final i in h)
          if (g[i] == 0 && cand[i] & SudokuSolver.bit(solutionDigit) != 0) i,
      ];
      if (spots.length == 1 && spots.first == idx) {
        return SudokuHintExplanation(
          solutionDigit,
          'Bu ${names[k]} $solutionDigit rakamının yazılabileceği tek boş '
          'hücre burası.',
        );
      }
    }
    return null;
  }
}
