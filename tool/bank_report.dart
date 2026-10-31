// ignore_for_file: avoid_print
// Banka özeti: dart tool/bank_report.dart
import 'bank_all.dart';

void main() {
  final byCat = <String, int>{};
  var l2 = 0;
  for (final w in allWords) {
    byCat[w.$3] = (byCat[w.$3] ?? 0) + 1;
    if (w.$4 == 2) l2++;
  }
  print('Geçerli giriş: ${allWords.length} (seviye 2: $l2)');
  print(byCat);
  print('Elenen: ${bankProblems.length}');
  for (final p in bankProblems) {
    print('  $p');
  }
}
