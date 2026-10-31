import '../core/turkish.dart';
import 'puzzle.dart';
import 'sudoku_solver.dart';
import 'word_structure.dart';

/// İçerik doğrulayıcı. Hata listesi boşsa bulmaca yayımlanabilir.
class ContentValidator {
  ContentValidator._();

  static const maxCengelClueChars = 70;
  static const maxClueChars = 160;

  /// [deep] false ise Sudoku için pahalı çözüm sayma/derecelendirme atlanır
  /// (yalnızca biçim ve kural çakışması denetlenir). Paketlenmiş içerik
  /// testlerde ve üretimde her zaman tam doğrulanır; uygulama açılışı hızlı
  /// kalsın diye çalışma anında hafif mod kullanılır.
  static List<String> validate(PuzzleDefinition p, {bool deep = true}) {
    final errors = <String>[];
    void err(String m) => errors.add('[${p.id}] $m');

    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{2,}$').hasMatch(p.id)) {
      err('Kimlik küçük harf/rakam/-/_ içermeli ve en az 3 karakter olmalı');
    }
    if (p.version < 1) err('Sürüm 1 veya daha büyük olmalı');
    if (p.title.trim().isEmpty) err('Başlık boş');
    if (p.source.trim().isEmpty) err('Kaynak bilgisi boş');
    if (p.license.trim().isEmpty) err('Lisans bilgisi boş');

    if (p.type == PuzzleType.sudoku) {
      _sudoku(p, err, deep: deep);
    } else {
      _word(p, err);
    }
    return errors;
  }

  /// Havuz düzeyi denetim: yinelenen kimlikler.
  static List<String> validatePool(List<PuzzleDefinition> pool) {
    final errors = <String>[];
    final seen = <String>{};
    for (final p in pool) {
      if (!seen.add(p.id)) errors.add('Yinelenen bulmaca kimliği: ${p.id}');
      errors.addAll(validate(p));
    }
    return errors;
  }

  static void _sudoku(
    PuzzleDefinition p,
    void Function(String) err, {
    bool deep = true,
  }) {
    if (p.givens.length != 81 || p.solution.length != 81) {
      err('Sudoku 81 karakter olmalı');
      return;
    }
    if (!RegExp(r'^[0-9.]{81}$').hasMatch(p.givens) ||
        !RegExp(r'^[1-9]{81}$').hasMatch(p.solution)) {
      err('Sudoku yalnızca rakam içermeli');
      return;
    }
    final sol = SudokuSolver.parse(p.solution);
    if (SudokuSolver.hasConflict(sol)) err('Çözüm kurallara aykırı');
    final giv = SudokuSolver.parse(p.givens);
    for (var i = 0; i < 81; i++) {
      if (giv[i] != 0 && giv[i] != sol[i]) {
        err('Başlangıç sayısı çözümle çelişiyor (hücre $i)');
        return;
      }
    }
    if (!deep) return;
    final r = SudokuSolver.countSolutions(giv, limit: 2);
    if (r.exhausted) {
      err('Çözüm sayısı bütçe içinde doğrulanamadı');
    } else if (r.count != 1) {
      err('Sudoku tam olarak tek çözümlü olmalı (bulunan: ${r.count})');
    } else if (SudokuSolver.encode(r.first!) != p.solution) {
      err('Bulunan tek çözüm bildirilen çözümle aynı değil');
    }
    if (r.count == 1 && SudokuSolver.rate(giv) != p.difficulty) {
      err(
        'Bildirilen zorluk (${p.difficulty.key}) mantıksal derecelendirme '
        '(${SudokuSolver.rate(giv).key}) ile uyuşmuyor',
      );
    }
  }

  static void _word(PuzzleDefinition p, void Function(String) err) {
    if (p.rows < 3 || p.cols < 3 || p.rows > 25 || p.cols > 25) {
      err('Izgara boyutu 3..25 aralığında olmalı');
      return;
    }
    if (p.grid.length != p.rows) {
      err('Izgara satır sayısı rows ile uyuşmuyor');
      return;
    }
    for (var r = 0; r < p.rows; r++) {
      final letters = Turkish.letters(p.grid[r]);
      if (letters.length != p.cols) {
        err('Satır $r uzunluğu ${letters.length}, beklenen ${p.cols}');
        return;
      }
      for (final ch in letters) {
        if (ch != '#' && !Turkish.alphabet.contains(ch)) {
          err('Satır $r içinde geçersiz karakter "$ch"');
          return;
        }
      }
    }
    final g = [for (final row in p.grid) Turkish.letters(row)];
    bool letter(int r, int c) =>
        r >= 0 && c >= 0 && r < p.rows && c < p.cols && g[r][c] != '#';

    if (p.entries.isEmpty) {
      err('Hiç cevap yok');
      return;
    }
    final ids = <String>{};
    final answers = <String>{};
    final covered = <int>{};
    final keyed = <String, WordEntry>{};
    for (final e in p.entries) {
      if (!ids.add(e.id)) err('Yinelenen giriş kimliği ${e.id}');
      if (!Turkish.isValidAnswer(e.answer)) {
        err('${e.id}: cevap yalnızca harf içermeli ("${e.answer}")');
        continue;
      }
      if (Turkish.upper(e.answer) != e.answer) {
        err('${e.id}: cevap büyük harf olmalı');
      }
      if (e.length < 2) err('${e.id}: cevap en az 2 harf olmalı');
      if (!answers.add(e.answer)) {
        err('${e.id}: cevap tekrar ediyor (${e.answer})');
      }
      if (e.clue.trim().isEmpty) err('${e.id}: ipucu boş');
      final maxChars = p.type == PuzzleType.cengel
          ? maxCengelClueChars
          : maxClueChars;
      if (e.clue.length > maxChars) {
        err('${e.id}: ipucu çok uzun (${e.clue.length} > $maxChars)');
      }
      if (p.type == PuzzleType.klasik && e.category.isEmpty) {
        err('${e.id}: klasik bulmacada kategori zorunlu');
      }
      final letters = Turkish.letters(e.answer);
      var fits = true;
      for (var i = 0; i < letters.length; i++) {
        final r = e.row + e.dir.dr * i, c = e.col + e.dir.dc * i;
        if (!letter(r, c)) {
          err(
            '${e.id}: cevap ızgaraya sığmıyor veya blok hücreye denk geliyor',
          );
          fits = false;
          break;
        }
        if (g[r][c] != letters[i]) {
          err(
            '${e.id}: ($r,$c) hücresinde "${g[r][c]}" var ama cevap '
            '"${letters[i]}" bekliyor (kesişim uyuşmuyor)',
          );
          fits = false;
          break;
        }
        covered.add(r * p.cols + c);
      }
      if (!fits) continue;
      // Cevap dizisi hem öncesinde hem sonrasında bitmeli.
      if (letter(e.row - e.dir.dr, e.col - e.dir.dc)) {
        err('${e.id}: cevap başlangıcından önce de harf hücresi var');
      }
      if (letter(e.row + e.dir.dr * e.length, e.col + e.dir.dc * e.length)) {
        err('${e.id}: cevaptan sonra da harf hücresi var');
      }
      if (keyed['${e.dir.key}@${e.row},${e.col}'] != null) {
        err('${e.id}: aynı başlangıçta iki cevap');
      }
      keyed['${e.dir.key}@${e.row},${e.col}'] = e;
      if (p.type == PuzzleType.cengel) {
        if (!e.hasClueCell ||
            e.clueRow >= p.rows ||
            e.clueCol >= p.cols ||
            letter(e.clueRow, e.clueCol)) {
          err('${e.id}: soru hücresi ızgara içinde ve oynanamaz olmalı');
        }
      } else if (e.hasClueCell) {
        err('${e.id}: kare/klasik girişlerinde soru hücresi olmamalı');
      }
    }

    // Izgaradaki her ≥2 uzunluklu harf dizisi bir cevaba karşılık gelmeli.
    for (final dir in Dir.values) {
      for (var r = 0; r < p.rows; r++) {
        for (var c = 0; c < p.cols; c++) {
          if (!letter(r, c) || letter(r - dir.dr, c - dir.dc)) continue;
          var len = 0;
          while (letter(r + dir.dr * len, c + dir.dc * len)) {
            len++;
          }
          if (len < 2) continue;
          final e = keyed['${dir.key}@$r,$c'];
          if (e == null) {
            err(
              '($r,$c) hücresinden başlayan ${dir.label} dizisi için cevap '
              'tanımlı değil (ulaşılamayan dizi)',
            );
          } else if (e.length != len) {
            err('${e.id}: cevap uzunluğu dizi uzunluğuyla uyuşmuyor');
          }
        }
      }
    }
    // Her harf hücresi en az bir cevaba ait olmalı.
    var letterCells = 0;
    for (var r = 0; r < p.rows; r++) {
      for (var c = 0; c < p.cols; c++) {
        if (!letter(r, c)) continue;
        letterCells++;
        if (!covered.contains(r * p.cols + c)) {
          err('($r,$c) hücresi hiçbir cevaba ait değil (boşta kalan hücre)');
        }
      }
    }
    if (letterCells == 0) return;

    // Çengel: soru hücresi başına en çok bir cevap/yön ve numaralandırma.
    if (p.type == PuzzleType.cengel) {
      final used = <String>{};
      for (final e in p.entries) {
        if (!used.add('${e.clueRow},${e.clueCol},${e.dir.key}')) {
          err('${e.id}: soru hücresinde aynı yön için ikinci ipucu var');
        }
      }
    } else {
      final nums = WordStructure.numbering(p.rows, p.cols, letter);
      for (final e in p.entries) {
        final expected = nums[e.row * p.cols + e.col];
        if (expected != e.number) {
          err('${e.id}: numara ${e.number}, beklenen $expected');
        }
      }
    }

    // Bağlantılılık (harf hücreleri 4 komşulukla tek parça).
    final start = covered.isEmpty ? null : covered.first;
    if (start != null) {
      final seen = <int>{start};
      final stack = [start];
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        final r = i ~/ p.cols, c = i % p.cols;
        for (final (dr, dc) in const [(0, 1), (1, 0), (0, -1), (-1, 0)]) {
          if (letter(r + dr, c + dc)) {
            final j = (r + dr) * p.cols + c + dc;
            if (seen.add(j)) stack.add(j);
          }
        }
      }
      if (seen.length != letterCells) {
        err('Izgara tek parça değil (${seen.length}/$letterCells bağlantılı)');
      }
    }
  }
}
