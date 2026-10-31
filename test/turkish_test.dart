import 'package:bulmaca_postasi/core/turkish.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('i ve ı Türkçe kurallarına göre büyür', () {
    expect(Turkish.upper('iıçğöşü'), 'İIÇĞÖŞÜ');
    expect(Turkish.upper('istanbul'), 'İSTANBUL');
    expect(Turkish.upper('ışık'), 'IŞIK');
  });

  test('küçültme de Türkçe kurallarına uyar', () {
    expect(Turkish.lower('İI'), 'iı');
    expect(Turkish.lower('ÇĞÖŞÜ'), 'çğöşü');
  });

  test('birleşik karakterler normalize edilir ve tek harf sayılır', () {
    const decomposed = 'İ'; // I + birleştirici nokta = İ
    expect(Turkish.normalize(decomposed), 'İ');
    expect(Turkish.letterCount('ÇİĞ'), 3);
    expect(Turkish.letterCount('Ş'), 1); // S + cedilla → Ş
  });

  test('Ş ile S, İ ile I eşdeğer sayılmaz', () {
    expect(Turkish.upper('ş') == Turkish.upper('s'), isFalse);
    expect(Turkish.upper('i') == Turkish.upper('ı'), isFalse);
  });

  test('giriş yalnızca tek geçerli harf kabul eder', () {
    expect(Turkish.inputLetter('ş'), 'Ş');
    expect(Turkish.inputLetter('i'), 'İ');
    expect(Turkish.inputLetter('ı'), 'I');
    expect(Turkish.inputLetter('ab'), isNull);
    expect(Turkish.inputLetter('5'), isNull);
    expect(Turkish.inputLetter(' '), isNull);
    expect(Turkish.inputLetter(''), isNull);
  });

  test('cevap sözleşmesi boşluk, tire ve kesmeyi reddeder', () {
    expect(Turkish.isValidAnswer('KARA DENİZ'), isFalse);
    expect(Turkish.isValidAnswer('AY-IŞIĞI'), isFalse);
    expect(Turkish.isValidAnswer("ANKARA'DA"), isFalse);
    expect(Turkish.isValidAnswer('KARADENİZ'), isTrue);
  });
}
