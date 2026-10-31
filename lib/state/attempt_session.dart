import 'package:flutter/foundation.dart';

import '../domain/attempt.dart';
import '../domain/newspaper.dart';
import '../domain/play_timer.dart';
import '../domain/puzzle.dart';
import '../domain/puzzle_game.dart';
import '../domain/sudoku_game.dart';
import '../domain/word_game.dart';

/// Oturumun bağlı olduğu uygulama katmanı.
abstract interface class SessionHost {
  void activate(AttemptSession s);
  void persist(AttemptSession s);
  void completed(AttemptSession s);
}

/// Tek bir denemenin canlı durumu. Sayfa görünümü ve odak modu *aynı*
/// nesneyi kullanır; iki ayrı kopya yoktur.
class AttemptSession extends ChangeNotifier {
  AttemptSession({
    required this.meta,
    required this.def,
    required this.game,
    required this.timer,
    required this.host,
  });

  final AttemptMeta meta;
  final PuzzleDefinition def;
  final PuzzleGame game;
  final PlayTimer timer;
  final SessionHost host;

  /// Yeni tamamlandığında bir kez true olur; arayüz kutlamayı gösterip
  /// [consumeCompletion] ile temizler.
  bool justCompleted = false;

  /// Kullanıcıya gösterilecek kısa, geçici ileti (kontrol sonucu vb.).
  String? notice;

  WordGame? get word => game is WordGame ? game as WordGame : null;
  SudokuGame? get sudoku => game is SudokuGame ? game as SudokuGame : null;

  AttemptStatus get status {
    if (meta.completed) return AttemptStatus.completed;
    if (meta.touched || game.progress > 0 || game.hintCount > 0) {
      return AttemptStatus.inProgress;
    }
    return AttemptStatus.notStarted;
  }

  int get elapsedMs => timer.elapsedMs;
  bool get assisted => game.hintedCellCount > 0 || game.hintCount > 0;

  /// Oyun durumunu değiştirir; kaydeder; çözüm tamamlandıysa bir kez bildirir.
  /// [edit] false ise yalnızca seçim gibi geçici bir değişikliktir.
  void mutate(void Function() change, {bool edit = true, String? message}) {
    final wasSolved = meta.completed;
    change();
    notice = message;
    if (edit) meta.touched = true;
    if (!wasSolved && game.isSolved) {
      timer.pause();
      meta.completedAtMs = DateTime.now().millisecondsSinceEpoch;
      justCompleted = true;
      meta.elapsedMs = timer.elapsedMs;
      host.completed(this);
    }
    meta.elapsedMs = timer.elapsedMs;
    host.persist(this);
    notifyListeners();
  }

  /// Bu bulmaca üzerinde etkileşim başladı: süre bunun için işler.
  void activate() => host.activate(this);

  void consumeCompletion() {
    justCompleted = false;
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    ...meta.toJson(),
    'elapsedMs': timer.elapsedMs,
    'state': game.toJson(),
  };

  void touchNotify() => notifyListeners();
}
