import 'puzzle.dart';

/// Sayfa şablonları veridir, koda gömülü sabit düzen değildir: yeni bir şablon
/// eklemek yalnızca bu listeye satır eklemektir.
const pageTemplates = <List<PuzzleType>>[
  [PuzzleType.cengel, PuzzleType.sudoku],
  [PuzzleType.kare, PuzzleType.klasik],
  [PuzzleType.sudoku, PuzzleType.kare],
  [PuzzleType.klasik, PuzzleType.cengel],
  [PuzzleType.cengel, PuzzleType.kare],
  [PuzzleType.sudoku, PuzzleType.klasik],
];

/// Bir yuva için planlanan içerik.
class PlannedSlot {
  const PlannedSlot(this.type, this.difficulty, this.puzzle);
  final PuzzleType type;
  final Difficulty difficulty;
  final PuzzleDefinition puzzle;
}

class IssuePlanner {
  IssuePlanner._();

  static const pagesPerIssue = 4;

  /// Günlük sayı planı: yalnızca tarih (ve havuz) belirler. Aynı girdilerle
  /// her zaman aynı sonuç döner. [seenPuzzleIds] önceden verilmiş bulmacalardır;
  /// havuz izin verdiği sürece onlardan kaçınılır.
  static List<List<PlannedSlot>> plan({
    required int dateSeed,
    required List<PuzzleDefinition> pool,
    Set<String> seenPuzzleIds = const {},
    int pages = pagesPerIssue,
  }) {
    final usedHere = <String>{};
    final result = <List<PlannedSlot>>[];
    for (var p = 0; p < pages; p++) {
      final template = pageTemplates[(dateSeed + p) % pageTemplates.length];
      final row = <PlannedSlot>[];
      for (var s = 0; s < 2; s++) {
        final type = template[s];
        final diff = Difficulty.values[(dateSeed + p * 2 + s) % 3];
        final pick = pickFor(
          type: type,
          difficulty: diff,
          pool: pool,
          avoid: {...usedHere, ...seenPuzzleIds},
          fallbackAvoid: usedHere,
          salt: dateSeed + p * 7 + s * 3,
        );
        if (pick == null) continue;
        usedHere.add(pick.id);
        row.add(PlannedSlot(type, pick.difficulty, pick));
      }
      if (row.length == 2) result.add(row);
    }
    return result;
  }

  /// Önce istenen zorlukta ve kaçınılmayan, sonra kaçınılmayan başka zorlukta,
  /// sonra yalnızca [fallbackAvoid] dışı seçer. Hiçbiri yoksa null.
  static PuzzleDefinition? pickFor({
    required PuzzleType type,
    required Difficulty difficulty,
    required List<PuzzleDefinition> pool,
    required Set<String> avoid,
    Set<String> fallbackAvoid = const {},
    int salt = 0,
  }) {
    final ofType = pool.where((p) => p.type == type).toList();
    List<PuzzleDefinition> sameDiff(Set<String> a) => ofType
        .where((p) => p.difficulty == difficulty && !a.contains(p.id))
        .toList();
    List<PuzzleDefinition> anyDiff(Set<String> a) =>
        ofType.where((p) => !a.contains(p.id)).toList();
    for (final c in [
      sameDiff(avoid),
      anyDiff(avoid),
      sameDiff(fallbackAvoid),
      anyDiff(fallbackAvoid),
    ]) {
      if (c.isNotEmpty) return c[salt.abs() % c.length];
    }
    return null;
  }
}
