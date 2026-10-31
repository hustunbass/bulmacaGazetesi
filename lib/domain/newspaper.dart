import 'puzzle.dart';

/// Sayfadaki iki bulmaca yuvasından biri. Yuva bir "deneme"ye (attempt)
/// bağlıdır; "Yeni bulmaca" eski denemeyi [history]ye arşivler.
class PuzzleSlot {
  PuzzleSlot({
    required this.id,
    required this.type,
    required this.difficulty,
    required this.attemptId,
    List<String>? history,
  }) : history = history ?? [];

  final String id;

  /// İstenen tür/zorluk (yeni bulmacada korunur; kullanıcı değiştirebilir).
  PuzzleType type;
  Difficulty difficulty;
  String attemptId;
  final List<String> history;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.key,
    'difficulty': difficulty.key,
    'attempt': attemptId,
    'history': history,
  };

  factory PuzzleSlot.fromJson(Map<String, dynamic> j) => PuzzleSlot(
    id: j['id'] as String,
    type: PuzzleType.parse(j['type']),
    difficulty: Difficulty.parse(j['difficulty']),
    attemptId: j['attempt'] as String,
    history: [for (final h in (j['history'] as List? ?? const [])) '$h'],
  );
}

class NewspaperPage {
  NewspaperPage({required this.index, required this.slots});
  final int index;
  final List<PuzzleSlot> slots;

  Map<String, dynamic> toJson() => {
    'index': index,
    'slots': [for (final s in slots) s.toJson()],
  };

  factory NewspaperPage.fromJson(Map<String, dynamic> j) => NewspaperPage(
    index: j['index'] as int,
    slots: [
      for (final s in (j['slots'] as List))
        PuzzleSlot.fromJson(s as Map<String, dynamic>),
    ],
  );
}

/// Bir günlük gazete sayısı. Kimliği tarihten (yerel gün) türer ve saklanır;
/// aynı gün içinde yeniden açıldığında yeniden üretilmez.
class NewspaperIssue {
  NewspaperIssue({
    required this.id,
    required this.date,
    required this.number,
    required this.pages,
  });

  final String id;
  final DateTime date;
  final int number;
  final List<NewspaperPage> pages;

  Iterable<PuzzleSlot> get slots => pages.expand((p) => p.slots);

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'date': id,
    'number': number,
    'pages': [for (final p in pages) p.toJson()],
  };

  factory NewspaperIssue.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return NewspaperIssue(
      id: id,
      date: parseIssueDate(id),
      number: j['number'] as int,
      pages: [
        for (final p in (j['pages'] as List))
          NewspaperPage.fromJson(p as Map<String, dynamic>),
      ],
    );
  }

  static String idFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parseIssueDate(String id) {
    final p = id.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  /// Sayı numarası: uygulamanın ilk açıldığı gün ([since]) 1. Sayı; sonraki her
  /// takvim günü 1 artar (telefonun yerel tarihine göre). Telefon saati
  /// kurulum gününden önceye alınırsa numara 1'in altına inmez.
  static int numberFor(DateTime d, {required DateTime since}) {
    final base = DateTime.utc(since.year, since.month, since.day);
    final day = DateTime.utc(d.year, d.month, d.day);
    final n = day.difference(base).inDays + 1;
    return n < 1 ? 1 : n;
  }
}

/// Bir denemenin yaşam durumu.
enum AttemptStatus { notStarted, inProgress, completed }
