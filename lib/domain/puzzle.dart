import '../core/turkish.dart';

class ContentException implements Exception {
  ContentException(this.message);
  final String message;
  @override
  String toString() => 'ContentException: $message';
}

enum PuzzleType {
  cengel('cengel', 'Çengel bulmaca', 'Çengel'),
  kare('kare', 'Kare bulmaca', 'Kare'),
  klasik('klasik', 'Klasik bulmaca', 'Klasik'),
  sudoku('sudoku', 'Sudoku', 'Sudoku');

  const PuzzleType(this.key, this.label, this.shortLabel);
  final String key;
  final String label;
  final String shortLabel;

  bool get isWord => this != sudoku;

  static PuzzleType parse(Object? v) => PuzzleType.values.firstWhere(
    (t) => t.key == v,
    orElse: () => throw ContentException('Bilinmeyen bulmaca türü: $v'),
  );
}

enum Difficulty {
  kolay('kolay', 'Kolay'),
  orta('orta', 'Orta'),
  zor('zor', 'Zor');

  const Difficulty(this.key, this.label);
  final String key;
  final String label;

  static Difficulty parse(Object? v) => Difficulty.values.firstWhere(
    (d) => d.key == v,
    orElse: () => throw ContentException('Bilinmeyen zorluk: $v'),
  );
}

enum Dir {
  across('A', 'Soldan sağa', 0, 1),
  down('D', 'Yukarıdan aşağıya', 1, 0);

  const Dir(this.key, this.label, this.dr, this.dc);
  final String key;
  final String label;
  final int dr;
  final int dc;

  Dir get other => this == across ? down : across;

  static Dir parse(Object? v) => Dir.values.firstWhere(
    (d) => d.key == v,
    orElse: () => throw ContentException('Bilinmeyen yön: $v'),
  );
}

/// Kelime bulmacasındaki tek bir cevap dizisi.
///
/// Çengelde ipucu ızgara içindeki bir soru hücresindedir ([clueRow],
/// [clueCol]); cevap yön okunun gösterdiği ilk hücrede başlar. Kare/klasikte
/// ([number]) numaralı hücrede başlar ve [clueRow] < 0'dır.
class WordEntry {
  const WordEntry({
    required this.id,
    required this.dir,
    required this.row,
    required this.col,
    required this.answer,
    required this.clue,
    this.number = 0,
    this.clueRow = -1,
    this.clueCol = -1,
    this.category = '',
  });

  final String id;
  final Dir dir;

  /// Cevabın ilk harfinin konumu.
  final int row;
  final int col;
  final String answer;
  final String clue;
  final int number;
  final int clueRow;
  final int clueCol;
  final String category;

  int get length => Turkish.letterCount(answer);
  bool get hasClueCell => clueRow >= 0;

  List<(int, int)> get cells => [
    for (var i = 0; i < length; i++) (row + dir.dr * i, col + dir.dc * i),
  ];
}

class PuzzleDefinition {
  const PuzzleDefinition({
    required this.id,
    required this.version,
    required this.type,
    required this.difficulty,
    required this.title,
    required this.source,
    required this.license,
    required this.rows,
    required this.cols,
    this.grid = const [],
    this.entries = const [],
    this.givens = '',
    this.solution = '',
  });

  final String id;
  final int version;
  final PuzzleType type;
  final Difficulty difficulty;
  final String title;
  final String source;
  final String license;
  final int rows;
  final int cols;

  /// Kelime bulmacası: her satır; harf = cevap hücresi, `#` = oynanamaz hücre.
  final List<String> grid;
  final List<WordEntry> entries;

  /// Sudoku: 81 karakter, `0` boş.
  final String givens;
  final String solution;

  factory PuzzleDefinition.fromJson(Map<String, dynamic> j) {
    T need<T>(String k) {
      final v = j[k];
      if (v is! T) {
        throw ContentException('"$k" alanı eksik veya hatalı (${j['id']})');
      }
      return v;
    }

    final type = PuzzleType.parse(j['type']);
    final entries = <WordEntry>[];
    if (type.isWord) {
      final raw = need<List>('entries');
      for (final e in raw) {
        if (e is! Map) {
          throw ContentException('Geçersiz giriş kaydı (${j['id']})');
        }
        final dir = Dir.parse(e['dir']);
        final answer = Turkish.upper((e['answer'] ?? '') as String);
        if (type == PuzzleType.cengel) {
          final cr = e['clueR'], cc = e['clueC'];
          if (cr is! int || cc is! int) {
            throw ContentException(
              'Çengel girişinde clueR/clueC yok (${e['id']})',
            );
          }
          entries.add(
            WordEntry(
              id: '${e['id']}',
              dir: dir,
              clueRow: cr,
              clueCol: cc,
              row: dir == Dir.down ? cr + 1 : cr,
              col: dir == Dir.across ? cc + 1 : cc,
              answer: answer,
              clue: '${e['clue']}',
              category: '${e['cat'] ?? ''}',
            ),
          );
        } else {
          final r = e['r'], c = e['c'], n = e['n'];
          if (r is! int || c is! int || n is! int) {
            throw ContentException('Giriş r/c/n alanları eksik (${e['id']})');
          }
          entries.add(
            WordEntry(
              id: '${e['id']}',
              dir: dir,
              row: r,
              col: c,
              number: n,
              answer: answer,
              clue: '${e['clue']}',
              category: '${e['cat'] ?? ''}',
            ),
          );
        }
      }
    }
    return PuzzleDefinition(
      id: need<String>('id'),
      version: need<int>('version'),
      type: type,
      difficulty: Difficulty.parse(j['difficulty']),
      title: need<String>('title'),
      source: need<String>('source'),
      license: need<String>('license'),
      rows: type.isWord ? need<int>('rows') : 9,
      cols: type.isWord ? need<int>('cols') : 9,
      grid: type.isWord
          ? need<List>('grid').map((e) => Turkish.upper('$e')).toList()
          : const [],
      entries: entries,
      givens: type.isWord ? '' : need<String>('givens'),
      solution: type.isWord ? '' : need<String>('solution'),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'version': version,
    'type': type.key,
    'difficulty': difficulty.key,
    'title': title,
    'source': source,
    'license': license,
    if (type.isWord) ...{
      'rows': rows,
      'cols': cols,
      'grid': grid,
      'entries': [
        for (final e in entries)
          if (type == PuzzleType.cengel)
            {
              'id': e.id,
              'dir': e.dir.key,
              'clueR': e.clueRow,
              'clueC': e.clueCol,
              'answer': e.answer,
              'clue': e.clue,
            }
          else
            {
              'id': e.id,
              'n': e.number,
              'dir': e.dir.key,
              'r': e.row,
              'c': e.col,
              'answer': e.answer,
              'clue': e.clue,
              if (e.category.isNotEmpty) 'cat': e.category,
            },
      ],
    } else ...{
      'givens': givens,
      'solution': solution,
    },
  };

  int get cellCount => rows * cols;
}
