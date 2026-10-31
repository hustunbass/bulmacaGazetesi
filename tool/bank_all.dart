// Tüm kelime bankası: ana banka + konu bankaları. Yinelenen cevaplar (ilk
// geçen kazanır) ve geçersiz girişler elenir; neden `bankProblems` içinde.
import 'package:bulmaca_postasi/core/turkish.dart';

import 'bank_a.dart';
import 'bank_b.dart';
import 'bank_c.dart';
import 'bank_d.dart';
import 'word_bank.dart';

final List<String> bankProblems = [];

final List<Word> allWords = _merge([wordBank, bankA, bankB, bankC, bankD]);

List<Word> _merge(List<List<Word>> lists) {
  final seen = <String>{};
  final out = <Word>[];
  for (final list in lists) {
    for (final w in list) {
      final (a, clue, cat, lvl) = w;
      if (!Turkish.isValidAnswer(a) || Turkish.upper(a) != a) {
        bankProblems.add('Geçersiz cevap: $a');
      } else if (Turkish.letterCount(a) < 3 || Turkish.letterCount(a) > 11) {
        bankProblems.add('Uzunluk dışı: $a');
      } else if (clue.trim().isEmpty || clue.length > 70) {
        bankProblems.add('İpucu uygun değil: $a');
      } else if (lvl != 1 && lvl != 2) {
        bankProblems.add('Seviye geçersiz: $a');
      } else if (!seen.add(a)) {
        bankProblems.add('Yinelenen cevap: $a');
      } else {
        out.add(w);
      }
    }
  }
  return out;
}
