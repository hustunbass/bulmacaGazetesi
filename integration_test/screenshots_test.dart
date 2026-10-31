// App Store ekran görüntüleri. Simülatörde çalışır:
//
//   tool/take_screenshots.sh <simulator-udid> <çıktı-klasörü>
//
// Test gerçek uygulamayı (gerçek fontlar, gerçek içerik) sürer; her ekranda
// /tmp/shot_req dosyasına ad yazar, ana makinedeki betik `simctl io screenshot`
// ile çekip /tmp/shot_done oluşturur. Durum temiz bir geçici dizindedir.
import 'dart:io';

import 'package:bulmaca_postasi/core/clock.dart';
import 'package:bulmaca_postasi/data/content_library.dart';
import 'package:bulmaca_postasi/data/file_store.dart';
import 'package:bulmaca_postasi/domain/puzzle.dart';
import 'package:bulmaca_postasi/state/app_controller.dart';
import 'package:bulmaca_postasi/state/attempt_session.dart';
import 'package:bulmaca_postasi/state/providers.dart';
import 'package:bulmaca_postasi/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 600));
  final done = File('/tmp/shot_done');
  if (done.existsSync()) done.deleteSync();
  File('/tmp/shot_req').writeAsStringSync(name);
  for (var i = 0; i < 100 && !done.existsSync(); i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

AttemptSession sessionOf(AppController c, PuzzleType type, {int nth = 0}) {
  final list = [
    for (final s in c.issue!.slots)
      if (c.sessionFor(s)!.def.type == type) c.sessionFor(s)!,
  ];
  return list[nth];
}

/// Çözümün [ratio] kadarını doğru yazar (bazı hücreler boş kalır).
void fillWord(AttemptSession s, double ratio, {int skipEvery = 0}) {
  final w = s.word!;
  s.mutate(() {
    var n = 0;
    for (var i = 0; i < w.solution.length; i++) {
      if (w.solution[i].isEmpty) continue;
      n++;
      if (skipEvery > 0 && n % skipEvery == 0) continue;
      if (n / w.solution.where((e) => e.isNotEmpty).length > ratio) break;
      w.selCell = i;
      w.inputLetter(w.solution[i]);
    }
    w.selCell = -1;
  });
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('app store ekran görüntüleri', (t) async {
    final dir = await Directory.systemTemp.createTemp('shots');
    final lib = await ContentLibrary.loadAssets(rootBundle);
    final c = AppController(
      store: FileStore(dir),
      library: lib,
      clock: StopwatchClock(),
      now: () => DateTime(2026, 10, 30, 9),
    );
    await c.init();
    // Tablet yatay çekim: --dart-define=ORIENTATION=landscape
    const orientation = String.fromEnvironment('ORIENTATION');
    if (orientation == 'landscape') {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
      ]);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    c.updateSettings(c.settings.copyWith(onboardingDone: true, sound: false));
    await t.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => c)],
        child: const BulmacaApp(),
      ),
    );
    await t.pumpAndSettle(const Duration(milliseconds: 300));

    // --- Durumları hazırla: gerçekçi, kısmen çözülmüş bulmacalar ---
    final sudoku = sessionOf(c, PuzzleType.sudoku);
    sudoku.mutate(() {
      final g = sudoku.sudoku!;
      var n = 0;
      for (var i = 0; i < 81; i++) {
        if (g.isGiven(i)) continue;
        n++;
        if (n % 3 == 0) continue;
        g.select(i);
        g.inputDigit(g.solution[i]);
      }
      // Birkaç aday notu.
      for (var i = 0; i < 81 && g.notes.where((x) => x != 0).length < 6; i++) {
        if (g.isGiven(i) || g.values[i] != 0) continue;
        g.select(i);
        g.noteMode = true;
        g.inputDigit(g.solution[i]);
        g.inputDigit(g.solution[i] % 9 + 1);
        g.noteMode = false;
      }
      g.select(-1);
    }, edit: true);
    final kare = sessionOf(c, PuzzleType.kare);
    fillWord(kare, 0.62, skipEvery: 7);
    final cengel = sessionOf(c, PuzzleType.cengel);
    fillWord(cengel, 0.55, skipEvery: 5);
    final klasik = sessionOf(c, PuzzleType.klasik);
    fillWord(klasik, 0.35, skipEvery: 6);
    await t.pumpAndSettle(const Duration(milliseconds: 300));

    // 1) Gazete sayfası
    await shot(t, '1_gazete_sayfasi');

    // 2) Sayfa çevirme (kıvrılma anı): animasyon çok yavaşlatılır, kıvrılmanın
    // ortasında durup çekilir (parmak/dokunma göstergesi görüntüye girmez).
    timeDilation = 100;
    await t.tap(find.byTooltip('Sonraki sayfa'));
    await t.pump();
    // 520 ms × 100 = 52 sn sürer; ~%40'ında (≈21 sn) çek.
    for (var i = 0; i < 210; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await shot(t, '2_sayfa_cevirme');
    timeDilation = 1;
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    // İlk sayfaya dön.
    await t.tap(find.byTooltip('Önceki sayfa'));
    await t.pumpAndSettle(const Duration(milliseconds: 400));

    Future<void> openFocus(AttemptSession s) async {
      final slot = c.issue!.slots.firstWhere((x) => c.sessionFor(x) == s);
      final pageIndex = c.issue!.pages.indexWhere(
        (p) => p.slots.contains(slot),
      );
      final nav = Navigator.of(t.element(find.byType(Scaffold).first));
      // Doğru sayfaya git (düğmelerle).
      final now = find.textContaining('Sayfa ').evaluate().isNotEmpty;
      if (now) {
        for (var i = 0; i < 6; i++) {
          final cur = find.textContaining('Sayfa ${pageIndex + 1} / ');
          if (cur.evaluate().isNotEmpty) break;
          final tip = find.byTooltip('Sonraki sayfa');
          if (tip.evaluate().isEmpty) break;
          await t.tap(tip);
          await t.pumpAndSettle(const Duration(milliseconds: 300));
        }
      }
      expect(nav, isNotNull);
      final slotIndex = c.issue!.pages[pageIndex].slots.indexOf(slot);
      await t.tap(find.byTooltip('Büyüt ve oyna').at(slotIndex));
      await t.pumpAndSettle(const Duration(milliseconds: 400));
    }

    // 3) Kare bulmaca odak modu: yeşil kelime + kırmızı yanlış harf + klavye.
    await openFocus(kare);
    kare.mutate(() {
      final w = kare.word!;
      // Yanlış bir harf: ilk boş hücreye bilerek yanlış harf yaz.
      final empty = w.solution.indexWhere((s) => s.isNotEmpty);
      var target = -1;
      for (var i = 0; i < w.letters.length; i++) {
        if (w.solution[i].isNotEmpty && w.letters[i].isEmpty) {
          target = i;
          break;
        }
      }
      if (target >= 0 && empty >= 0) {
        w.selCell = target;
        w.inputLetter(w.solution[target] == 'Z' ? 'Y' : 'Z');
      }
      // Seçili cevap: yarım kalmış bir cevap.
      for (var k = 0; k < w.structure.entries.length; k++) {
        final cells = w.structure.entryCells(k);
        if (!w.isEntryCorrect(k) && cells.any((x) => w.letters[x].isEmpty)) {
          w.selectEntry(k);
          break;
        }
      }
    }, edit: false);
    await t.pumpAndSettle(const Duration(milliseconds: 300));
    await shot(t, '3_kare_bulmaca');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle(const Duration(milliseconds: 400));

    // 4) Sudoku odak modu
    await openFocus(sudoku);
    sudoku.mutate(() {
      final g = sudoku.sudoku!;
      final i = List.generate(
        81,
        (k) => k,
      ).firstWhere((k) => !g.isGiven(k) && g.values[k] == 0);
      g.select(i);
    }, edit: false);
    await t.pumpAndSettle(const Duration(milliseconds: 300));
    await shot(t, '4_sudoku');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle(const Duration(milliseconds: 400));

    // 5) Çengel odak modu
    await openFocus(cengel);
    cengel.mutate(() {
      final w = cengel.word!;
      for (var k = 0; k < w.structure.entries.length; k++) {
        final cells = w.structure.entryCells(k);
        if (!w.isEntryCorrect(k) && cells.any((x) => w.letters[x].isEmpty)) {
          w.selectEntry(k);
          break;
        }
      }
    }, edit: false);
    await t.pumpAndSettle(const Duration(milliseconds: 300));
    await shot(t, '5_cengel');
    File('/tmp/shot_req').writeAsStringSync('__bitti__');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle(const Duration(milliseconds: 300));
  });
}
