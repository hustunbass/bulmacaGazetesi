/// Kelime bulmacası ve Sudoku motorlarının oturum/kayıt katmanına gösterdiği
/// ortak yüz. Motorlar widget'lardan bağımsızdır.
abstract class PuzzleGame {
  /// Doldurulmuş oynanabilir hücre oranı (0..1). Doğruluk bilgisi sızdırmaz.
  double get progress;

  bool get isSolved;

  /// Açılan ipucu sayısı (harf/cevap/hücre eylemleri).
  int get hintCount;

  /// İpucuyla açılmış hücre sayısı.
  int get hintedCellCount;

  int get checkCount;

  bool get canUndo;
  bool get canRedo;

  Map<String, dynamic> toJson();
}

/// Kontrol sonucu. Boş hücreler yanlış sayılmaz.
class CheckResult {
  const CheckResult({
    required this.correct,
    required this.wrong,
    required this.empty,
  });

  final int correct;
  final int wrong;
  final int empty;

  bool get allCorrect => wrong == 0 && empty == 0;
}

/// Kayıtlı oyun durumu okunamadığında fırlatılır; kayıt izole edilir.
class CorruptStateException implements Exception {
  CorruptStateException(this.message);
  final String message;
  @override
  String toString() => 'CorruptStateException: $message';
}
