import 'puzzle.dart';

/// Tamamlama kaydı. Aynı deneme için yalnızca bir kez yazılır.
class CompletionRecord {
  const CompletionRecord({
    required this.attemptId,
    required this.puzzleId,
    required this.type,
    required this.difficulty,
    required this.elapsedMs,
    required this.hintCount,
    required this.completedAtMs,
  });

  final String attemptId;
  final String puzzleId;
  final PuzzleType type;
  final Difficulty difficulty;
  final int elapsedMs;
  final int hintCount;
  final int completedAtMs;

  bool get assisted => hintCount > 0;

  Map<String, dynamic> toJson() => {
    'attempt': attemptId,
    'puzzle': puzzleId,
    'type': type.key,
    'difficulty': difficulty.key,
    'elapsedMs': elapsedMs,
    'hints': hintCount,
    'at': completedAtMs,
  };

  factory CompletionRecord.fromJson(Map<String, dynamic> j) => CompletionRecord(
    attemptId: j['attempt'] as String,
    puzzleId: j['puzzle'] as String,
    type: PuzzleType.parse(j['type']),
    difficulty: Difficulty.parse(j['difficulty']),
    elapsedMs: j['elapsedMs'] as int,
    hintCount: j['hints'] as int,
    completedAtMs: j['at'] as int,
  );
}

/// Bir bulmaca denemesinin üst verisi. Oyun durumu ayrı tutulur (`state`).
/// Deneme, başladığı bulmaca *sürümüne* bağlıdır: içerik güncellenirse
/// açık denemeler eski sürümle çözülmeye devam eder.
class AttemptMeta {
  AttemptMeta({
    required this.id,
    required this.puzzleId,
    required this.puzzleVersion,
    required this.issueId,
    required this.slotId,
    required this.createdAtMs,
    this.elapsedMs = 0,
    this.completedAtMs,
    this.completionRecorded = false,
    this.archived = false,
    this.touched = false,
  });

  final String id;
  final String puzzleId;
  final int puzzleVersion;
  final String issueId;
  final String slotId;
  final int createdAtMs;
  int elapsedMs;
  int? completedAtMs;
  bool completionRecorded;
  bool archived;

  /// Kullanıcı bu denemeyle etkileşime girdi mi (başlandı sayılır).
  bool touched;

  bool get completed => completedAtMs != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'puzzle': puzzleId,
    'version': puzzleVersion,
    'issue': issueId,
    'slot': slotId,
    'created': createdAtMs,
    'elapsedMs': elapsedMs,
    if (completedAtMs != null) 'completed': completedAtMs,
    'recorded': completionRecorded,
    'archived': archived,
    'touched': touched,
  };

  factory AttemptMeta.fromJson(Map<String, dynamic> j) => AttemptMeta(
    id: j['id'] as String,
    puzzleId: j['puzzle'] as String,
    puzzleVersion: j['version'] as int,
    issueId: j['issue'] as String,
    slotId: j['slot'] as String,
    createdAtMs: j['created'] as int,
    elapsedMs: j['elapsedMs'] as int,
    completedAtMs: j['completed'] as int?,
    completionRecorded: j['recorded'] as bool? ?? false,
    archived: j['archived'] as bool? ?? false,
    touched: j['touched'] as bool? ?? false,
  );
}
