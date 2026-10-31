import 'dart:math';

import 'puzzle.dart';
import 'sudoku_solver.dart';

class GeneratedSudoku {
  const GeneratedSudoku(this.givens, this.solution, this.difficulty);
  final String givens;
  final String solution;
  final Difficulty difficulty;
}

/// Yerel Sudoku üretimi. Her aday bulmaca tek çözüm ve istenen mantıksal
/// zorluk için doğrulanır; deneme sayısı sınırlıdır, sonsuz döngü yoktur.
/// Başarısız olursa null döner (çağıran açıkça bildirmelidir).
GeneratedSudoku? generateSudoku(
  Difficulty difficulty,
  int seed, {
  int maxAttempts = 60,
}) {
  final rng = Random(seed);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final solution = SudokuSolver.randomSolution(rng);
    final g = List<int>.from(solution);
    final order = List<int>.generate(81, (i) => i)..shuffle(rng);
    final minClues = switch (difficulty) {
      Difficulty.kolay => 34,
      Difficulty.orta => 28,
      Difficulty.zor => 22,
    };
    var clues = 81;
    for (final i in order) {
      if (clues <= minClues) break;
      final keep = g[i];
      g[i] = 0;
      final ok = switch (difficulty) {
        Difficulty.kolay => SudokuSolver.solvableBySingles(g, hidden: false),
        Difficulty.orta => SudokuSolver.solvableBySingles(g, hidden: true),
        Difficulty.zor => () {
          final r = SudokuSolver.countSolutions(g, limit: 2, maxNodes: 20000);
          return r.count == 1 && !r.exhausted;
        }(),
      };
      if (ok) {
        clues--;
      } else {
        g[i] = keep;
      }
    }
    // Tek çözüm son kez kesin doğrulanır.
    final check = SudokuSolver.countSolutions(g, limit: 2);
    if (check.count != 1 || check.exhausted) continue;
    if (SudokuSolver.rate(g) != difficulty) continue;
    return GeneratedSudoku(
      SudokuSolver.encode(g),
      SudokuSolver.encode(solution),
      difficulty,
    );
  }
  return null;
}

/// `compute` ile ana iş parçacığı dışında çalıştırmak için üst düzey giriş.
GeneratedSudoku? generateSudokuIsolate((int, int) args) =>
    generateSudoku(Difficulty.values[args.$1], args.$2);
