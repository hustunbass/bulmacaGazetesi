import 'dart:io';

import 'package:bulmaca_postasi/core/clock.dart';
import 'package:bulmaca_postasi/data/file_store.dart';
import 'package:bulmaca_postasi/data/settings.dart';
import 'package:bulmaca_postasi/domain/attempt.dart';
import 'package:bulmaca_postasi/domain/puzzle.dart';
import 'package:bulmaca_postasi/state/app_controller.dart';
import 'package:bulmaca_postasi/state/providers.dart';
import 'package:bulmaca_postasi/ui/format.dart';
import 'package:bulmaca_postasi/ui/screens/archive_screen.dart';
import 'package:bulmaca_postasi/ui/screens/onboarding_screen.dart';
import 'package:bulmaca_postasi/ui/screens/settings_screen.dart';
import 'package:bulmaca_postasi/ui/screens/stats_screen.dart';
import 'package:bulmaca_postasi/ui/theme.dart';
import 'package:bulmaca_postasi/ui/widgets/paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Directory? dir;
late AppController ctl;

Future<void> boot(WidgetTester tester) async {
  await tester.runAsync(() async {
    final d = await Directory.systemTemp.createTemp('bulmaca_screens');
    dir = d;
    ctl = AppController(
      store: FileStore(d),
      library: loadLibraryFromDisk(),
      clock: FakeClock(),
      now: () => DateTime(2026, 10, 30, 9),
    );
    await ctl.init();
  });
}

Widget host(Widget child) => ProviderScope(
  overrides: [appControllerProvider.overrideWith((ref) => ctl)],
  child: MaterialApp(theme: buildTheme(PaperTheme.ivory), home: child),
);

CompletionRecord rec(
  String id,
  PuzzleType t,
  Difficulty d,
  int ms,
  int hints,
) => CompletionRecord(
  attemptId: id,
  puzzleId: 'p$id',
  type: t,
  difficulty: d,
  elapsedMs: ms,
  hintCount: hints,
  completedAtMs: 1,
);

void main() {
  setUp(() => PaperTexture.enabled = false);

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      // Denetleyiciyi ProviderScope kaldırılırken kendisi dispose eder.
      await dir?.delete(recursive: true);
      dir = null;
    } on Object {
      // geçici dizin; işletim sistemi temizler
    }
  });

  test('formatDuration', () {
    expect(formatDuration(425000), '7:05');
    expect(formatDuration(3729000), '1:02:09');
    expect(formatDuration(0), '0:00');
  });

  testWidgets('istatistik: veri yoksa boş durum', (tester) async {
    await boot(tester);
    await tester.pumpWidget(host(const StatsScreen()));
    expect(
      find.textContaining('Henüz tamamlanmış bulmaca yok'),
      findsOneWidget,
    );
  });

  testWidgets('istatistik: yardımlı süreler hesaba katılmaz', (tester) async {
    await boot(tester);
    ctl.completions = [
      rec('a', PuzzleType.kare, Difficulty.kolay, 60000, 0),
      rec('b', PuzzleType.kare, Difficulty.kolay, 120000, 0),
      rec('c', PuzzleType.kare, Difficulty.kolay, 5000, 2),
    ];
    await tester.pumpWidget(host(const StatsScreen()));
    expect(
      find.textContaining('3 tamamlandı · 2 yardımsız · 1 yardımlı'),
      findsOneWidget,
    );
    expect(find.textContaining('En iyi 1:00 · Ortalama 1:30'), findsOneWidget);
  });

  testWidgets('ayarlar: anahtar ayarı değiştirir; tanıtım yeniden gösterilir', (
    tester,
  ) async {
    await boot(tester);
    await tester.pumpWidget(host(const SettingsScreen()));
    expect(ctl.settings.sound, isTrue, reason: 'ses varsayılan olarak açık');
    await tester.tap(find.textContaining('Ses (kalem'));
    await tester.pump();
    expect(ctl.settings.sound, isFalse);

    ctl.settings = ctl.settings.copyWith(onboardingDone: true);
    await tester.scrollUntilVisible(find.text('Tanıtımı tekrar göster'), 200);
    await tester.ensureVisible(find.text('Tanıtımı tekrar göster'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tanıtımı tekrar göster'));
    await tester.pump();
    expect(ctl.settings.onboardingDone, isFalse);
    expect(find.textContaining('yeniden gösterilecek'), findsOneWidget);
    await tester.runAsync(() => ctl.store.flush());
  });

  testWidgets('ayarlar: kayıt hatasında Yeniden dene görünür', (tester) async {
    await boot(tester);
    ctl.store.saveError.value = 'İlerleme kaydedilemedi: deneme';
    await tester.pumpWidget(host(const SettingsScreen()));
    expect(find.text('Yeniden dene'), findsOneWidget);
    ctl.store.saveError.value = null;
    await tester.pump();
    expect(find.text('Yeniden dene'), findsNothing);
  });

  testWidgets('ayarlar: büyük yazıda taşma yok', (tester) async {
    await boot(tester);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(2.0),
          size: Size(360, 640),
        ),
        child: host(const SettingsScreen()),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('arşiv: sayı satırı görünür ve açılır', (tester) async {
    await boot(tester);
    await tester.runAsync(() => ctl.store.flush());
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? opened;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ArchiveScreen(onOpenIssue: (id) async => opened = id),
                ),
              ),
              child: const Text('git'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('git'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // gerçek dosya G/Ç
    bool loaded() =>
        find.textContaining('Başlanmadı').evaluate().isNotEmpty ||
        find.textContaining('Devam ediyor').evaluate().isNotEmpty;
    for (var i = 0; i < 200 && !loaded(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    expect(find.textContaining('30 Ekim 2026, Cuma'), findsOneWidget);
    expect(find.textContaining('Başlanmadı'), findsWidgets);
    await tester.tap(find.textContaining('30 Ekim 2026, Cuma').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, '2026-10-30');
    expect(find.text('git'), findsOneWidget); // ekran kapandı
  });

  testWidgets(
    'tanıtım: ileri ile ilerler, Başla onDone çağırır; Atla da çağırır',
    (tester) async {
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(PaperTheme.ivory),
          home: OnboardingScreen(onDone: () => done++),
        ),
      );
      expect(find.text('Sayfaları çevirin'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('İleri'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Kare, Klasik ve Çengel'), findsOneWidget);
      await tester.tap(find.text('Başla'));
      expect(done, 1);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(PaperTheme.ivory),
          home: OnboardingScreen(key: UniqueKey(), onDone: () => done++),
        ),
      );
      await tester.tap(find.text('Atla'));
      expect(done, 2);
    },
  );
}
