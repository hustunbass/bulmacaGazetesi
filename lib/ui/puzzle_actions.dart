import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ads.dart';
import '../domain/newspaper.dart';
import '../domain/puzzle.dart';
import '../domain/puzzle_game.dart';
import '../state/app_controller.dart';
import '../state/attempt_session.dart';
import 'format.dart';
import 'theme.dart';

/// Bir bulmacanın menü eylemleri: ipucu, kontrol, sıfırla, yeni bulmaca.
/// Sayfa kartı ve odak modu aynı eylemleri paylaşır.
class PuzzleActions {
  PuzzleActions._();

  static void say(BuildContext context, String message) {
    final m = ScaffoldMessenger.maybeOf(context);
    m
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  static void tap(AppController c) {
    if (c.settings.haptics) HapticFeedback.selectionClick();
  }

  // ------------------------------------------------------------------ ipucu

  static Future<void> hint(
    BuildContext context,
    AppController c,
    AttemptSession s,
  ) async {
    s.activate();
    final w = s.word;
    if (w != null) {
      final choice = await _menu<String>(context, 'İpucu', [
        _Opt(
          'letter',
          Icons.text_fields,
          'Seçili harfi aç',
          'Yalnızca seçili hücredeki harf açılır ve kilitlenir.',
        ),
        _Opt(
          'answer',
          Icons.spellcheck,
          'Seçili cevabı aç',
          'Seçili cevabın tüm harfleri açılır. Onay istenir.',
        ),
      ]);
      if (choice == null || !context.mounted) return;
      if (w.selCell < 0) {
        say(context, 'Önce bir hücre seçin.');
        return;
      }
      if (choice == 'letter') {
        if (w.hinted[w.selCell]) {
          say(context, 'Bu harf zaten açık.');
          return;
        }
        if (c.ads.enabled &&
            !await _unlockWithAd(
              context,
              c,
              title: 'Harfi aç?',
              body:
                  'Bu harfi açmak için kısa bir reklam izlemeniz gerekir. '
                  'Reklam bitince harf açılır ve bulmaca “yardımlı” sayılır.',
              action: 'Reklamı izle',
            )) {
          return;
        }
        if (!context.mounted) return;
        s.mutate(
          () => w.hintLetter(),
          message: 'Harf açıldı. Bu bulmaca yardımlı sayılır.',
        );
        say(context, '${_takeNote()}Harf açıldı. Bu bulmaca yardımlı sayılır.');
      } else {
        final n = w.activeCells.where((x) => !w.hinted[x]).length;
        if (n == 0) {
          say(context, 'Bu cevap zaten açık.');
          return;
        }
        final body =
            'Seçili cevabın kalan $n harfi açılacak ve kilitlenecek. '
            'Bu, geri alınamaz ve bulmaca “yardımlı” sayılır.';
        if (!context.mounted) return;
        bool? ok;
        if (c.ads.enabled) {
          ok = await _unlockWithAd(
            context,
            c,
            title: 'Cevabı aç?',
            body:
                '$body\n\nBunun için kısa bir reklam izlemeniz gerekir; '
                'reklam bitince cevap açılır.',
            action: 'Reklamı izle',
          );
        } else {
          ok = await confirm(
            context,
            title: 'Cevabı aç?',
            body: body,
            action: 'Cevabı aç',
          );
        }
        if (ok != true || !context.mounted) return;
        s.mutate(() => w.hintEntryAnswer(), message: 'Cevap açıldı.');
        if (context.mounted) {
          say(
            context,
            '${_takeNote()}Cevap açıldı. Bu bulmaca yardımlı sayılır.',
          );
        }
      }
      return;
    }
    final g = s.sudoku!;
    if (g.selCell < 0 || g.isLocked(g.selCell)) {
      say(
        context,
        g.selCell < 0 ? 'Önce boş bir hücre seçin.' : 'Bu hücre zaten sabit.',
      );
      return;
    }
    final h = g.previewHint();
    if (h == null) return;
    if (c.ads.enabled) {
      // Açıklama ipucunun kendisidir: reklamdan sonra gösterilir.
      final go = await _unlockWithAd(
        context,
        c,
        title: 'Hücreyi aç?',
        body:
            'Bu hücreyi açmak için kısa bir reklam izlemeniz gerekir. Reklam '
            'bitince hücre açılır, kilitlenir ve bulmaca “yardımlı” sayılır.',
        action: 'Reklamı izle',
      );
      if (go != true || !context.mounted) return;
      s.mutate(() => g.applyHint(), message: 'Hücre açıldı.');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hücre açıldı'),
          content: Text(
            _takeNote() +
                (h.explanation ??
                    'Bu hücre için kısa bir mantıksal açıklama tespit edilemedi. '
                        'Hücre doğrudan açıldı.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sudoku ipucu', style: serifStyle(ctx.pal.ink, 20)),
              const SizedBox(height: 10),
              Text(
                h.explanation ??
                    'Bu hücre için kısa bir mantıksal açıklama tespit edilemedi. '
                        'Hücreyi doğrudan açabilirsiniz.',
                style: sansStyle(ctx.pal.ink, 16, h: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Açılan hücre kilitlenir ve bulmaca “yardımlı” sayılır.',
                style: sansStyle(ctx.pal.inkSoft, 14),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Hücreyi aç'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    s.mutate(() => g.applyHint(), message: 'Hücre açıldı.');
    say(context, 'Hücre açıldı. Bu bulmaca yardımlı sayılır.');
  }

  /// İpucu için ödüllü reklam adımı. true dönerse ipucu verilir:
  /// * reklam izlendi → verilir;
  /// * reklam yarıda kapatıldı → verilmez;
  /// * reklam yüklenemedi (çevrimdışı vb.) → oyun çevrimdışı kullanılabilsin
  ///   diye ipucu yine verilir ve kullanıcıya söylenir.
  static String _giftNote = '';

  static String _takeNote() {
    final n = _giftNote;
    _giftNote = '';
    return n;
  }

  static Future<bool> _unlockWithAd(
    BuildContext context,
    AppController c, {
    required String title,
    required String body,
    required String action,
  }) async {
    final go = await confirm(context, title: title, body: body, action: action);
    if (go != true || !context.mounted) return false;
    final r = await c.ads.showRewarded();
    if (!context.mounted) return false;
    switch (r) {
      case RewardOutcome.earned:
        return true;
      case RewardOutcome.dismissed:
        say(context, 'Reklam tamamlanmadığı için ipucu verilmedi.');
        return false;
      case RewardOutcome.unavailable:
        // Mesaj, ipucunun kendi bildirimiyle birleşsin (biri ötekini ezmesin).
        _giftNote = 'Reklam şu an yüklenemedi; ipucu bu seferlik hediye. ';
        return true;
    }
  }

  // ----------------------------------------------------------------- kontrol

  static Future<void> check(
    BuildContext context,
    AppController c,
    AttemptSession s,
  ) async {
    s.activate();
    final w = s.word;
    if (w == null) {
      final g = s.sudoku!;
      late CheckResult r;
      s.mutate(() => r = g.check(), message: null);
      say(context, _wordMessage(r, c.settings.highlightErrors));
      return;
    }
    final choice = await _menu<String>(context, 'Kontrol', [
      _Opt(
        'entry',
        Icons.rule,
        'Seçili cevabı kontrol et',
        'Yalnızca seçili cevaptaki harfler denetlenir; doğru cevap yazılmaz.',
      ),
      _Opt(
        'all',
        Icons.fact_check_outlined,
        'Tüm bulmacayı kontrol et',
        'Dolu hücreler cevap anahtarına göre denetlenir. Boş hücreler yanlış sayılmaz.',
      ),
    ]);
    if (choice == null || !context.mounted) return;
    if (choice == 'entry' && w.activeEntry == null) {
      say(context, 'Önce bir cevap seçin.');
      return;
    }
    late CheckResult r;
    s.mutate(() => r = choice == 'entry' ? w.checkEntry() : w.checkAll());
    say(context, _wordMessage(r, c.settings.highlightErrors));
  }

  static String _wordMessage(CheckResult r, bool highlight) {
    if (r.allCorrect) return 'Hepsi doğru.';
    final parts = <String>[
      if (r.wrong > 0)
        '${r.wrong} hücre yanlış${highlight ? ' (işaretlendi)' : ''}'
      else
        'Yanlış yok',
      if (r.empty > 0) '${r.empty} hücre boş',
      '${r.correct} doğru',
    ];
    return '${parts.join(', ')}.';
  }

  // ---------------------------------------------------------- sıfırla / yeni

  static Future<void> reset(
    BuildContext context,
    AppController c,
    PuzzleSlot slot,
  ) async {
    final ok = await confirm(
      context,
      title: 'Bulmacayı baştan başlat?',
      body:
          'Aynı bulmaca baştan başlar. Yazdıklarınız, notlarınız, açılan ipuçları '
          've süre silinir. Bulmaca ve çözümü değişmez; sayfadaki diğer bulmaca etkilenmez.',
      action: 'Sıfırla',
      destructive: true,
    );
    if (ok != true) return;
    await c.resetPuzzle(slot);
    if (context.mounted) say(context, 'Bulmaca baştan başlatıldı.');
  }

  static Future<void> newPuzzle(
    BuildContext context,
    AppController c,
    PuzzleSlot slot,
  ) async {
    final s = c.sessionFor(slot);
    if (s == null) return;
    var type = slot.type;
    var diff = slot.difficulty;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yeni bulmaca getir', style: serifStyle(ctx.pal.ink, 20)),
                const SizedBox(height: 8),
                Text(
                  'Bu yuvaya farklı bir bulmaca gelir. Şimdiki bulmacanın ilerlemesi '
                  'arşivde saklanır; sayfadaki diğer bulmaca değişmez.',
                  style: sansStyle(ctx.pal.ink, 15, h: 1.4),
                ),
                const SizedBox(height: 14),
                Text(
                  'Tür',
                  style: sansStyle(ctx.pal.inkSoft, 13, w: FontWeight.w700),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in PuzzleType.values)
                      ChoiceChip(
                        label: Text(t.shortLabel),
                        selected: type == t,
                        showCheckmark: true,
                        onSelected: (_) => setS(() => type = t),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Zorluk',
                  style: sansStyle(ctx.pal.inkSoft, 13, w: FontWeight.w700),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in Difficulty.values)
                      ChoiceChip(
                        label: Text(d.label),
                        selected: diff == d,
                        showCheckmark: true,
                        onSelected: (_) => setS(() => diff = d),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Yeni bulmaca'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Yeni bulmaca hazırlanıyor…'),
        duration: Duration(seconds: 1),
      ),
    );
    final r = await c.newPuzzle(slot, type: type, difficulty: diff);
    if (!context.mounted) return;
    say(context, switch (r) {
      NewPuzzleOutcome.replaced =>
        'Yeni bulmaca getirildi. Öncekine arşivden ulaşabilirsiniz.',
      NewPuzzleOutcome.exhausted =>
        'Bu türde uygun yeni bulmaca kalmadı. Mevcut bulmacanız olduğu gibi duruyor.',
      NewPuzzleOutcome.busy =>
        'Bu bulmaca için bir işlem sürüyor. Lütfen bekleyip tekrar deneyin.',
      NewPuzzleOutcome.generationFailed =>
        'Yeni Sudoku üretilemedi. Mevcut bulmacanız olduğu gibi duruyor; tekrar deneyebilirsiniz.',
    });
  }

  static Future<void> previous(
    BuildContext context,
    AppController c,
    PuzzleSlot slot,
  ) async {
    final list = await c.previousAttempts(slot);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Önceki denemeler', style: serifStyle(ctx.pal.ink, 20)),
              const SizedBox(height: 8),
              if (list.isEmpty)
                Text(
                  'Bu yuvada daha önce değiştirilmiş bulmaca yok.',
                  style: sansStyle(ctx.pal.ink, 15),
                )
              else
                for (final m in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      m.completed
                          ? Icons.check_circle_outline
                          : Icons.timelapse,
                      color: ctx.pal.inkSoft,
                    ),
                    title: Text(
                      c.library.byId(m.puzzleId)?.title ?? m.puzzleId,
                    ),
                    subtitle: Text(
                      '${m.completed ? 'Tamamlandı' : 'Yarım bırakıldı'} · ${formatDuration(m.elapsedMs)}',
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- yardımcılar

  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: ctx.pal.bad)
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
  }

  static Future<T?> _menu<T>(
    BuildContext context,
    String title,
    List<_Opt<T>> opts,
  ) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(title, style: serifStyle(ctx.pal.ink, 20)),
                  ),
                ),
                for (final o in opts)
                  ListTile(
                    leading: Icon(o.icon, color: ctx.pal.ink),
                    title: Text(
                      o.title,
                      style: sansStyle(ctx.pal.ink, 17, w: FontWeight.w700),
                    ),
                    subtitle: Text(o.sub),
                    minVerticalPadding: 10,
                    onTap: () => Navigator.pop(ctx, o.value),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Opt<T> {
  const _Opt(this.value, this.icon, this.title, this.sub);
  final T value;
  final IconData icon;
  final String title;
  final String sub;
}
