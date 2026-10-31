import 'dart:io';

import 'package:bulmaca_postasi/core/clock.dart';
import 'package:bulmaca_postasi/core/ads.dart';
import 'package:bulmaca_postasi/core/sfx.dart';
import 'package:bulmaca_postasi/data/file_store.dart';
import 'package:bulmaca_postasi/domain/puzzle.dart';
import 'package:bulmaca_postasi/state/app_controller.dart';
import 'package:bulmaca_postasi/state/providers.dart';
import 'package:bulmaca_postasi/ui/app.dart';
import 'package:bulmaca_postasi/ui/widgets/keyboards.dart';
import 'package:bulmaca_postasi/ui/widgets/paper.dart';
import 'package:bulmaca_postasi/ui/widgets/puzzle_card.dart';
import 'package:bulmaca_postasi/ui/widgets/sudoku_grid.dart';
import 'package:bulmaca_postasi/ui/widgets/word_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

late AppController ctl;

/// Gerçek dosya G/Ç'si `runAsync` içinde yapılır.
Future<void> boot(
  WidgetTester t, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
  bool reduceMotion = false,
  Sfx sfx = const NoopSfx(),
  Ads ads = const NoopAds(),
}) async {
  PaperTexture.enabled = false;
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('ui_test');
    ctl = AppController(
      store: FileStore(dir),
      library: loadLibraryFromDisk(),
      clock: FakeClock(),
      now: () => DateTime(2026, 10, 30, 9),
      sfx: sfx,
      ads: ads,
    );
    await ctl.init();
    ctl.updateSettings(
      ctl.settings.copyWith(
        onboardingDone: true,
        textScale: textScale,
        reduceMotion: reduceMotion,
        lastPage: 0,
      ),
    );
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => ctl)],
      child: const BulmacaApp(),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> shutdown(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Future<void> nextPage(WidgetTester t) async {
  await t.tap(find.byTooltip('Sonraki sayfa'));
  await t.pump();
  await t.pump(const Duration(seconds: 1));
}

void main() {
  soundTests();
  adsTests();
  liveFeedbackTests();
  tabletTests();
  testWidgets(
    'sayfada tam iki bulmaca, gazete künyesi ve sayfa göstergesi var',
    (t) async {
      await boot(t);
      expect(find.byType(PuzzleCard), findsNWidgets(2));
      expect(find.text('Bulmaca Gazetesi'), findsOneWidget);
      expect(find.textContaining('BULMACA EKİ'), findsOneWidget);
      expect(find.textContaining('30 Ekim 2026'), findsOneWidget);
      expect(find.text('1. SAYI'), findsOneWidget, reason: 'ilk gün 1. sayı');
      expect(find.textContaining('303'), findsNothing);
      expect(find.textContaining('Sayfa 1 / 4'), findsWidgets);
      expect(t.takeException(), isNull);
      await shutdown(t);
    },
  );

  testWidgets(
    'düğmelerle sayfa çevrilir; ilk sayfada geri, son sayfada ileri yoktur',
    (t) async {
      await boot(t, reduceMotion: true);
      IconButton btn(String tip) => t.widget<IconButton>(
        find.widgetWithIcon(
          IconButton,
          tip == 'p' ? Icons.chevron_left : Icons.chevron_right,
        ),
      );
      expect(btn('p').onPressed, isNull);
      for (var i = 2; i <= 4; i++) {
        await nextPage(t);
        expect(find.textContaining('Sayfa $i / 4'), findsWidgets);
        expect(find.byType(PuzzleCard), findsNWidgets(2));
      }
      expect(
        btn('n').onPressed,
        isNull,
        reason: 'son sayfadan ileri gidilemez',
      );
      await shutdown(t);
    },
  );

  testWidgets('kenardan sürükleyerek çevirme; yarım sürükleme geri döner', (
    t,
  ) async {
    await boot(t);
    // Yarım bırakılan sürükleme: sayfa değişmez.
    final g = await t.startGesture(const Offset(380, 400));
    await g.moveBy(const Offset(-40, 0));
    await t.pump();
    await g.up();
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Sayfa 1 / 4'), findsWidgets);
    // Tam sürükleme: sonraki sayfa.
    await t.dragFrom(const Offset(380, 400), const Offset(-330, 0));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Sayfa 2 / 4'), findsWidgets);
    // Sol kenardan geri.
    await t.dragFrom(const Offset(8, 400), const Offset(330, 0));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Sayfa 1 / 4'), findsWidgets);
    // İlk sayfada geri sürükleme sınırı aşamaz.
    await t.dragFrom(const Offset(8, 400), const Offset(330, 0));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Sayfa 1 / 4'), findsWidgets);
    await shutdown(t);
  });

  testWidgets('animasyon sürerken ikinci geçiş başlatılamaz', (t) async {
    await boot(t);
    await t.tap(find.byTooltip('Sonraki sayfa'));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byTooltip('Sonraki sayfa'));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(seconds: 2));
    expect(
      find.textContaining('Sayfa 2 / 4'),
      findsWidgets,
      reason: '3. sayfaya atlamamalı',
    );
    await shutdown(t);
  });

  testWidgets('sistem geri hareketi önce önceki sayfaya döner', (t) async {
    await boot(t, reduceMotion: true);
    await nextPage(t);
    await nextPage(t);
    expect(find.textContaining('Sayfa 3 / 4'), findsWidgets);
    await t.binding.handlePopRoute();
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Sayfa 2 / 4'), findsWidgets);
    await shutdown(t);
  });

  testWidgets('sayfa seçici sayfadaki iki türü ve doğrudan geçişi gösterir', (
    t,
  ) async {
    await boot(t, reduceMotion: true);
    await t.tap(find.byTooltip('Sayfa seçici').first);
    await t.pumpAndSettle();
    expect(find.text('Sayfalar'), findsOneWidget);
    expect(find.textContaining('  +  '), findsNWidgets(4));
    await t.tap(find.text('3').first);
    await t.pumpAndSettle();
    expect(find.textContaining('Sayfa 3 / 4'), findsWidgets);
    await shutdown(t);
  });

  testWidgets(
    'kelime bulmacası odak modu: Türkçe klavye harfi yazar, geri dönünce korunur',
    (t) async {
      await boot(t, reduceMotion: true);
      await nextPage(t); // sayfa 2: klasik + çengel (kelime bulmacaları)
      final slot = ctl.issue!.pages[1].slots[0];
      final s = ctl.sessionFor(slot)!;
      await t.tap(find.byTooltip('Büyüt ve oyna').first);
      await t.pumpAndSettle();
      expect(find.byType(TurkishKeyboard), findsOneWidget);
      for (final k in ['Ç', 'Ğ', 'İ', 'Ö', 'Ş', 'Ü', 'I']) {
        expect(
          find.widgetWithText(Material, k),
          findsWidgets,
          reason: 'tuş $k',
        );
      }
      await t.tap(find.byTooltip('Sonraki soru'));
      await t.pump();
      final w = s.word!;
      expect(w.activeEntry, isNotNull);
      await t.tap(find.text('Ş').last);
      await t.pump();
      expect(w.letters.contains('Ş'), isTrue);
      final sel = w.selCell;
      // Geri: sayfa aynı, giriş ve seçim korunur.
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.textContaining('Sayfa 2 / 4'), findsWidgets);
      expect(w.letters.contains('Ş'), isTrue);
      expect(w.selCell, sel);
      expect(
        ctl.sessionFor(slot),
        same(s),
        reason: 'aynı oyun durumu, kopya yok',
      );
      await shutdown(t);
    },
  );

  testWidgets('sudoku odak modu: sayı takımı, not modu, silme, geri al', (
    t,
  ) async {
    await boot(t, reduceMotion: true);
    final slot = ctl.issue!.slots.firstWhere(
      (x) => ctl.sessionFor(x)!.def.type == PuzzleType.sudoku,
    );
    final s = ctl.sessionFor(slot)!;
    final su = s.sudoku!;
    final cell = List.generate(81, (i) => i).firstWhere((i) => !su.isGiven(i));
    await t.tap(find.byTooltip('Büyüt ve oyna').first);
    await t.pumpAndSettle();
    expect(find.byType(NumberPad), findsOneWidget);
    expect(find.byType(SudokuGridView), findsOneWidget);
    s.mutate(() => su.select(cell), edit: false);
    await t.pump();
    await t.tap(find.text('5').last);
    await t.pump();
    expect(su.values[cell], 5);
    await t.tap(find.text('Geri al'));
    await t.pump();
    expect(su.values[cell], 0);
    await t.tap(find.text('Not'));
    await t.pump();
    expect(su.noteMode, isTrue);
    await t.tap(find.text('3').last);
    await t.pump();
    expect(su.notes[cell], isNot(0));
    await t.tap(find.text('Sil'));
    await t.pump();
    expect(su.notes[cell], 0);
    await shutdown(t);
  });

  testWidgets(
    'sıfırla onay ister; vazgeçince ilerleme korunur, onaylayınca aynı bulmaca baştan başlar',
    (t) async {
      await boot(t, reduceMotion: true);
      final slot = ctl.issue!.slots.firstWhere(
        (x) => ctl.sessionFor(x)!.def.type == PuzzleType.sudoku,
      );
      final s = ctl.sessionFor(slot)!;
      final su = s.sudoku!;
      final cell = List.generate(
        81,
        (i) => i,
      ).firstWhere((i) => !su.isGiven(i));
      s.mutate(() {
        su.select(cell);
        su.inputDigit(su.solution[cell]);
      });
      final puzzleId = s.def.id;
      final attemptId = s.meta.id;
      await t.tap(find.byTooltip('${s.def.title} menüsü'));
      await t.pumpAndSettle();
      await t.tap(find.text('Baştan başlat (sıfırla)'));
      await t.pumpAndSettle();
      expect(find.text('Bulmacayı baştan başlat?'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await t.pumpAndSettle();
      expect(ctl.sessionFor(slot)!.meta.id, attemptId);
      expect(su.values[cell], su.solution[cell]);
      await t.tap(find.byTooltip('${s.def.title} menüsü'));
      await t.pumpAndSettle();
      await t.tap(find.text('Baştan başlat (sıfırla)'));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.text('Sıfırla'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      final fresh = ctl.sessionFor(slot)!;
      expect(fresh.meta.id, isNot(attemptId));
      expect(fresh.def.id, puzzleId);
      expect(fresh.sudoku!.values[cell], 0);
      await shutdown(t);
    },
  );

  testWidgets('"yeni bulmaca" ve "sıfırla" ayrı açıklamalarla sunulur', (
    t,
  ) async {
    await boot(t, reduceMotion: true);
    final slot = ctl.issue!.pages[0].slots[0];
    final s = ctl.sessionFor(slot)!;
    await t.tap(find.byTooltip('${s.def.title} menüsü'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yeni bulmaca getir'));
    await t.pumpAndSettle();
    expect(find.textContaining('diğer bulmaca değişmez'), findsOneWidget);
    expect(find.textContaining('arşivde saklanır'), findsOneWidget);
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(
      ctl.sessionFor(slot),
      same(s),
      reason: 'vazgeçince hiçbir şey değişmez',
    );
    await shutdown(t);
  });

  testWidgets('küçük ekranda ve en büyük yazıda taşma olmaz', (t) async {
    await boot(t, size: const Size(320, 568), textScale: 1.4);
    expect(t.takeException(), isNull);
    expect(find.byType(PuzzleCard), findsNWidgets(2));
    await t.tap(find.byTooltip('Büyüt ve oyna').first);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Menü: arşiv, istatistikler, ayarlar'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await shutdown(t);
  });

  testWidgets('geniş ekranda iki bulmaca yan yana dizilir', (t) async {
    await boot(t, size: const Size(1024, 768));
    final cards = find.byType(PuzzleCard);
    expect(cards, findsNWidgets(2));
    final a = t.getTopLeft(cards.at(0)), b = t.getTopLeft(cards.at(1));
    expect(b.dx, greaterThan(a.dx + 300));
    expect((a.dy - b.dy).abs(), lessThan(4));
    expect(t.takeException(), isNull);
    await shutdown(t);
  });

  testWidgets('telefonda iki bulmaca alt alta dizilir', (t) async {
    await boot(t);
    final cards = find.byType(PuzzleCard);
    expect(
      t.getTopLeft(cards.at(1)).dy,
      greaterThan(t.getTopLeft(cards.at(0)).dy + 100),
    );
    await shutdown(t);
  });

  testWidgets(
    'ızgara ekran okuyucuya hücre bilgisi verir ama çözümü açıklamaz',
    (t) async {
      final h = t.ensureSemantics();
      await boot(t, reduceMotion: true);
      await nextPage(t); // kelime bulmacaları
      // ignore: deprecated_member_use
      final tree = t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!
          .toStringDeep();
      final labels = RegExp(r'label: "([^"]*)')
          .allMatches(tree)
          .map((m) => m.group(1)!)
          .where((l) => l.startsWith('Satır'))
          .toList();
      expect(labels, isNotEmpty);
      final empties = labels.where((l) => l.contains(', boş,'));
      expect(empties, isNotEmpty);
      for (final l in empties) {
        expect(
          l.contains('harf '),
          isFalse,
          reason: 'boş hücre etiketi harf içermemeli: $l',
        );
        expect(l.contains('düzenlenebilir'), isTrue);
      }
      // İlgili soru ve uzunluk bilgisi var.
      expect(
        labels.any((l) => l.contains('harf') && l.contains('Soldan sağa')),
        isTrue,
      );
      await shutdown(t);
      h.dispose();
    },
  );
}

class RecordingSfx implements Sfx {
  final log = <String>[];
  @override
  void pen() => log.add('pen');
  @override
  void erase() => log.add('erase');
  @override
  void page({bool back = false}) => log.add(back ? 'page-back' : 'page');
  @override
  Future<void> dispose() async {}
}

void tabletTests() {
  testWidgets('tablette klavye altta, tam genişlikte ve büyük tuşlarla gelir', (
    t,
  ) async {
    await boot(t, size: const Size(1024, 768), reduceMotion: true);
    // Sayfa 2: ilk yuva kelime bulmacası.
    await nextPage(t);
    await t.tap(find.byTooltip('Büyüt ve oyna').first);
    await t.pumpAndSettle();
    final kb = t.getRect(find.byType(TurkishKeyboard));
    final grid = t.getRect(find.byType(WordGridView));
    expect(kb.width, greaterThan(1000), reason: 'tam genişlik');
    expect(kb.bottom, greaterThan(768 - 60), reason: 'alt kenarda');
    expect(
      grid.bottom,
      lessThanOrEqualTo(kb.top + 1),
      reason: 'ızgara klavyenin üstünde',
    );
    final key = t.getRect(find.widgetWithText(Material, 'A').last);
    expect(key.height, greaterThanOrEqualTo(60));
    final letter = t.widget<Text>(
      find
          .descendant(
            of: find.byType(TurkishKeyboard),
            matching: find.text('A'),
          )
          .first,
    );
    expect(letter.style!.fontSize, 26, reason: 'tablet harf boyutu uygulanır');
    expect(t.takeException(), isNull);
    await shutdown(t);
  });
}

void liveFeedbackTests() {
  testWidgets(
    'yanlış harf anında işaretlenir, doğru kelime yeşil; ayar kapatılabilir',
    (t) async {
      await boot(t, reduceMotion: true);
      await nextPage(t);
      final slot = ctl.issue!.pages[1].slots[0];
      final s = ctl.sessionFor(slot)!;
      final w = s.word!;
      await t.tap(find.byTooltip('Büyüt ve oyna').first);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Sonraki soru'));
      await t.pump();
      final cells = w.activeCells;
      // Yanlış harf: oyun durumu yanlış der ve ekran okuyucu etiketi bunu içerir.
      final bad = w.solution[cells.first] == 'Z' ? 'Y' : 'Z';
      await t.tap(find.text(bad).last);
      await t.pump();
      expect(w.isLetterWrong(cells.first), isTrue);
      // Elle kontrol hâlâ çalışır ve doğru cevabı yazmaz.
      await t.tap(find.text('Kontrol'));
      await t.pumpAndSettle();
      expect(find.textContaining('Seçili cevabı kontrol et'), findsOneWidget);
      await t.tap(find.textContaining('Seçili cevabı kontrol et'));
      await t.pumpAndSettle();
      expect(w.letters[cells.first], bad, reason: 'kontrol düzeltmez');
      // Doğru yaz: kelime doğru olur.
      s.mutate(() {
        for (final c in cells) {
          w.selCell = c;
          w.inputLetter(w.solution[c]);
        }
      });
      await t.pump();
      expect(w.isEntryCorrect(w.activeEntry!), isTrue);
      expect(t.takeException(), isNull);
      // Ayarlardan kapatılınca çizim kapanır (oyun durumu aynı kalır).
      ctl.updateSettings(ctl.settings.copyWith(liveFeedback: false));
      await t.pump();
      expect(ctl.settings.liveFeedback, isFalse);
      expect(w.isEntryCorrect(w.activeEntry!), isTrue);
      await shutdown(t);
    },
  );
}

void soundTests() {
  testWidgets(
    'yazınca kalem, silince silgi, sayfa çevirince sayfa sesi çalar',
    (t) async {
      final sfx = RecordingSfx();
      await boot(t, reduceMotion: true, sfx: sfx);
      await nextPage(t);
      expect(sfx.log, ['page']);
      await t.tap(find.byTooltip('Büyüt ve oyna').first);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Sonraki soru'));
      await t.pump();
      await t.tap(find.text('Ş').last);
      await t.pump();
      await t.tap(find.text('A').last);
      await t.pump();
      expect(sfx.log.where((e) => e == 'pen').length, 2);
      await t.tap(find.byIcon(Icons.backspace_outlined).last);
      await t.pump();
      expect(sfx.log.last, 'erase');
      final n = sfx.log.length;
      // Boş hücrede silmek bir şeyi değiştirmez → ses yok.
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 1));
      expect(sfx.log.last, 'page-back');
      expect(sfx.log.length, n + 1);
      await shutdown(t);
    },
  );

  testWidgets('ses ayarı kapalıyken hiçbir ses çalmaz', (t) async {
    final sfx = RecordingSfx();
    await boot(t, reduceMotion: true, sfx: sfx);
    ctl.updateSettings(ctl.settings.copyWith(sound: false));
    await t.pump();
    await nextPage(t);
    await t.tap(find.byTooltip('Büyüt ve oyna').first);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Sonraki soru'));
    await t.pump();
    await t.tap(find.text('Ş').last);
    await t.pump();
    expect(sfx.log, isEmpty);
    await shutdown(t);
  });
}

/// Senaryolu sahte reklam servisi.
class FakeAds implements Ads {
  FakeAds(this.outcomes);
  final List<RewardOutcome> outcomes;
  int shown = 0;
  @override
  bool get enabled => true;
  @override
  Future<void> init() async {}
  @override
  Widget banner() =>
      const SizedBox(key: ValueKey('fake-banner'), height: 50, width: 320);
  @override
  Future<RewardOutcome> showRewarded() async {
    shown++;
    return outcomes.isEmpty ? RewardOutcome.unavailable : outcomes.removeAt(0);
  }

  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
}

Future<void> openWordFocus(WidgetTester t) async {
  await nextPage(t);
  await t.tap(find.byTooltip('Büyüt ve oyna').first);
  await t.pumpAndSettle();
  await t.tap(find.byTooltip('Sonraki soru'));
  await t.pump();
}

Future<void> chooseHint(WidgetTester t, String option) async {
  await t.tap(find.text('İpucu'));
  await t.pumpAndSettle();
  await t.tap(find.text(option));
  await t.pumpAndSettle();
}

void adsTests() {
  testWidgets('harf ipucu: reklam izlenirse harf açılır', (t) async {
    final ads = FakeAds([RewardOutcome.earned]);
    await boot(t, reduceMotion: true, ads: ads);
    await openWordFocus(t);
    final w = ctl.sessionFor(ctl.issue!.pages[1].slots[0])!.word!;
    await chooseHint(t, 'Seçili harfi aç');
    expect(find.text('Harfi aç?'), findsOneWidget);
    expect(ads.shown, 0, reason: 'onay verilmeden reklam gösterilmez');
    await t.tap(find.text('Reklamı izle'));
    await t.pumpAndSettle();
    expect(ads.shown, 1);
    expect(w.hintCount, 1);
    expect(w.hintedCellCount, 1);
    await shutdown(t);
  });

  testWidgets('reklam yarıda kapatılırsa ipucu verilmez', (t) async {
    final ads = FakeAds([RewardOutcome.dismissed]);
    await boot(t, reduceMotion: true, ads: ads);
    await openWordFocus(t);
    final w = ctl.sessionFor(ctl.issue!.pages[1].slots[0])!.word!;
    await chooseHint(t, 'Seçili harfi aç');
    await t.tap(find.text('Reklamı izle'));
    await t.pumpAndSettle();
    expect(ads.shown, 1);
    expect(w.hintCount, 0);
    expect(w.hintedCellCount, 0);
    expect(find.textContaining('ipucu verilmedi'), findsOneWidget);
    await shutdown(t);
  });

  testWidgets(
    'reklam yüklenemezse (çevrimdışı) ipucu yine verilir ve söylenir',
    (t) async {
      final ads = FakeAds([RewardOutcome.unavailable]);
      await boot(t, reduceMotion: true, ads: ads);
      await openWordFocus(t);
      final w = ctl.sessionFor(ctl.issue!.pages[1].slots[0])!.word!;
      await chooseHint(t, 'Seçili harfi aç');
      await t.tap(find.text('Reklamı izle'));
      await t.pumpAndSettle();
      expect(w.hintCount, 1);
      expect(find.textContaining('hediye'), findsOneWidget);
      await shutdown(t);
    },
  );

  testWidgets('dialogda vazgeçilirse reklam gösterilmez, ipucu verilmez', (
    t,
  ) async {
    final ads = FakeAds([RewardOutcome.earned]);
    await boot(t, reduceMotion: true, ads: ads);
    await openWordFocus(t);
    final w = ctl.sessionFor(ctl.issue!.pages[1].slots[0])!.word!;
    await chooseHint(t, 'Seçili harfi aç');
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(ads.shown, 0);
    expect(w.hintCount, 0);
    await shutdown(t);
  });

  testWidgets(
    'kelime ipucu: reklam izlenince tüm cevap açılır; yarıda kapanırsa açılmaz',
    (t) async {
      final ads = FakeAds([RewardOutcome.dismissed, RewardOutcome.earned]);
      await boot(t, reduceMotion: true, ads: ads);
      await openWordFocus(t);
      final w = ctl.sessionFor(ctl.issue!.pages[1].slots[0])!.word!;
      final cells = w.activeCells;
      await chooseHint(t, 'Seçili cevabı aç');
      expect(
        find.textContaining('kısa bir reklam izlemeniz gerekir'),
        findsOneWidget,
      );
      await t.tap(find.text('Reklamı izle'));
      await t.pumpAndSettle();
      expect(
        cells.every((c) => !w.hinted[c]),
        isTrue,
        reason: 'yarıda kapandı',
      );
      await chooseHint(t, 'Seçili cevabı aç');
      await t.tap(find.text('Reklamı izle'));
      await t.pumpAndSettle();
      expect(ads.shown, 2);
      expect(cells.every((c) => w.hinted[c]), isTrue);
      expect(w.hintCount, 1);
      await shutdown(t);
    },
  );

  testWidgets(
    'sudoku ipucu: reklamdan sonra hücre açılır ve açıklama gösterilir',
    (t) async {
      final ads = FakeAds([RewardOutcome.earned]);
      await boot(t, reduceMotion: true, ads: ads);
      final slot = ctl.issue!.slots.firstWhere(
        (x) => ctl.sessionFor(x)!.def.type == PuzzleType.sudoku,
      );
      final s = ctl.sessionFor(slot)!;
      final su = s.sudoku!;
      final cell = List.generate(
        81,
        (i) => i,
      ).firstWhere((i) => !su.isGiven(i));
      await t.tap(find.byTooltip('Büyüt ve oyna').first);
      await t.pumpAndSettle();
      s.mutate(() => su.select(cell), edit: false);
      await t.pump();
      await t.tap(find.text('İpucu'));
      await t.pumpAndSettle();
      expect(find.text('Hücreyi aç?'), findsOneWidget);
      expect(
        find.textContaining('mantıksal'),
        findsNothing,
        reason: 'açıklama reklamdan önce ifşa edilmez',
      );
      await t.tap(find.text('Reklamı izle'));
      await t.pumpAndSettle();
      expect(ads.shown, 1);
      expect(su.hintCount, 1);
      expect(su.values[cell], su.solution[cell]);
      expect(find.text('Hücre açıldı'), findsOneWidget);
      await shutdown(t);
    },
  );

  testWidgets('banner ana ekranda ve yeterince yüksek odak ekranında görünür', (
    t,
  ) async {
    await boot(t, reduceMotion: true, ads: FakeAds([]));
    expect(find.byKey(const ValueKey('fake-banner')), findsOneWidget);
    await t.tap(find.byTooltip('Büyüt ve oyna').first);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('fake-banner')), findsWidgets);
    await shutdown(t);
  });

  testWidgets('küçük ekranda odak modunda banner bulmaca alanını yemez', (
    t,
  ) async {
    await boot(
      t,
      size: const Size(360, 640),
      reduceMotion: true,
      ads: FakeAds([]),
    );
    await t.tap(find.byTooltip('Büyüt ve oyna').first);
    await t.pumpAndSettle();
    // Odak ekranı üstte: ana ekran bannerı arkada kalır, odak ekranına eklenmez.
    expect(t.takeException(), isNull);
    await shutdown(t);
  });

  testWidgets('reklamsız derlemede ipucu eskisi gibi (reklam adımı yok)', (
    t,
  ) async {
    await boot(t, reduceMotion: true);
    await openWordFocus(t);
    final w = ctl.sessionFor(ctl.issue!.pages[1].slots[0])!.word!;
    await chooseHint(t, 'Seçili harfi aç');
    expect(find.text('Reklamı izle'), findsNothing);
    expect(w.hintCount, 1);
    await shutdown(t);
  });
}
