/// Türkçe harf kuralları. Dart'ın yerleşik toUpperCase'i `i → I` yaptığı için
/// Türkçe için ayrı dönüşüm gerekir.
class Turkish {
  Turkish._();

  static const upperLetters = 'ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ';
  static const extraLatin = 'QWX';
  static final Set<String> alphabet = {
    ...upperLetters.split(''),
    ...extraLatin.split(''),
  };

  static String upper(String s) {
    final b = StringBuffer();
    for (final r in normalize(s).runes) {
      final ch = String.fromCharCode(r);
      b.write(switch (ch) {
        'i' => 'İ',
        'ı' => 'I',
        _ => ch.toUpperCase(),
      });
    }
    return b.toString();
  }

  static String lower(String s) {
    final b = StringBuffer();
    for (final r in normalize(s).runes) {
      final ch = String.fromCharCode(r);
      b.write(switch (ch) {
        'I' => 'ı',
        'İ' => 'i',
        _ => ch.toLowerCase(),
      });
    }
    return b.toString();
  }

  /// Türkçe harfler için NFC birleştirme (ör. `I` + U+0307 → `İ`).
  /// Yalnızca Türkçe'de gerçekten karşılaşılan birleşik dizileri kapsar.
  static const _compose = <String, String>{
    'İ': 'İ',
    'i̇': 'i',
    'Ç': 'Ç',
    'ç': 'ç',
    'Ğ': 'Ğ',
    'ğ': 'ğ',
    'Ö': 'Ö',
    'ö': 'ö',
    'Ş': 'Ş',
    'ş': 'ş',
    'Ü': 'Ü',
    'ü': 'ü',
  };

  static String normalize(String s) {
    if (!s.contains(RegExp('[̀-ͯ]'))) return s;
    var out = s;
    _compose.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  /// Gerçek harf (grapheme) sayısı. Birleşik karakterler normalize edildikten
  /// sonra Türkçe harflerin tamamı tek kod noktasıdır.
  static int letterCount(String s) => normalize(s).runes.length;

  static List<String> letters(String s) =>
      normalize(s).runes.map(String.fromCharCode).toList();

  /// Cevap sözleşmesi: yalnızca harf. Boşluk, kesme işareti ve tire ızgaraya
  /// yansımaz; cevap bu karakterler olmadan yazılır.
  static bool isValidAnswer(String s) =>
      s.isNotEmpty && letters(s).every(alphabet.contains);

  /// Kullanıcı girişini tek bir büyük harfe çevirir; geçersizse null.
  static String? inputLetter(String? s) {
    if (s == null || s.isEmpty) return null;
    final u = upper(s);
    final l = letters(u);
    if (l.length != 1) return null;
    return alphabet.contains(l.first) ? l.first : null;
  }
}
