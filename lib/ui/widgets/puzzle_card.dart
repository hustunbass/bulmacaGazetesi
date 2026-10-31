import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/newspaper.dart';
import '../../state/attempt_session.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../puzzle_actions.dart';
import '../screens/focus_screen.dart';
import '../theme.dart';
import 'sudoku_grid.dart';
import 'word_grid.dart';

/// Gazete sayfasındaki tek bir bulmaca yuvası: küçük başlık, tür, zorluk,
/// menü, önizleme ızgarası ve ilerleme. Dokunmak aynı oyunun odak moduna
/// geçirir.
class PuzzleCard extends ConsumerWidget {
  const PuzzleCard({super.key, required this.slot});
  final PuzzleSlot slot;

  Future<void> _open(
    BuildContext context,
    AttemptSession s, [
    int? cell,
  ]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FocusScreen(slot: slot, initialCell: cell),
      ),
    );
  }

  /// Izgarayı en-boy oranına oturtur: çevresinde boş şerit kalmaz.
  Widget _aspect(AttemptSession s, Widget grid) {
    final ratio = s.def.type.isWord ? s.def.cols / s.def.rows : 1.0;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620 * ratio),
        child: AspectRatio(aspectRatio: ratio, child: grid),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final pal = context.pal;
    final s = c.sessionFor(slot);
    if (s == null) {
      return _Problem(slot: slot, reason: c.problems[slot.id]?.reason);
    }
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final done = s.meta.completed;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(slot: slot, session: s, onOpen: () => _open(context, s)),
              const SizedBox(height: 6),
              Stack(
                alignment: Alignment.center,
                children: [
                  Semantics(
                    label: '${s.def.title}. Büyütmek için dokunun.',
                    child: _aspect(
                      s,
                      s.word != null
                          ? WordGridView(
                              session: s,
                              showWrong: c.settings.highlightErrors,
                              live: c.settings.liveFeedback,
                              onCellTap: (i) => _open(context, s, i),
                              onClueTap: (i) => _open(context, s),
                            )
                          : SudokuGridView(
                              session: s,
                              showConflicts: c.settings.sudokuShowConflicts,
                              onCellTap: (i) => _open(context, s, i),
                            ),
                    ),
                  ),
                  if (done) const IgnorePointer(child: _Stamp('ÇÖZÜLDÜ')),
                ],
              ),
              const SizedBox(height: 6),
              _Footer(session: s, showTimer: c.settings.showTimer),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  s.def.type.isWord
                      ? '${s.def.rows}×${s.def.cols} · ${s.def.entries.length} cevap'
                      : '9×9',
                  style: sansStyle(pal.inkSoft, 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.slot,
    required this.session,
    required this.onOpen,
  });
  final PuzzleSlot slot;
  final AttemptSession session;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final pal = context.pal;
    final s = session;
    final status = switch (s.status) {
      AttemptStatus.notStarted => (Icons.radio_button_unchecked, 'Başlanmadı'),
      AttemptStatus.inProgress => (Icons.timelapse, 'Devam ediyor'),
      AttemptStatus.completed => (Icons.check_circle_outline, 'Tamamlandı'),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.def.type.label.toUpperCase(),
                    style: sansStyle(
                      pal.accent,
                      12,
                      w: FontWeight.w800,
                      ls: 1.1,
                    ),
                  ),
                  Text(
                    s.def.title,
                    style: serifStyle(pal.ink, 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        s.def.difficulty.label,
                        style: sansStyle(pal.inkSoft, 13),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(
                                status.$1,
                                size: 14,
                                color: pal.inkSoft,
                              ),
                            ),
                            TextSpan(text: ' ${status.$2}'),
                          ],
                        ),
                        style: sansStyle(pal.inkSoft, 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Büyüt ve oyna',
          icon: const Icon(Icons.open_in_full),
          onPressed: onOpen,
        ),
        PopupMenuButton<String>(
          tooltip: '${s.def.title} menüsü',
          onSelected: (v) async {
            switch (v) {
              case 'open':
                onOpen();
              case 'check':
                await PuzzleActions.check(context, c, s);
              case 'hint':
                await PuzzleActions.hint(context, c, s);
              case 'reset':
                await PuzzleActions.reset(context, c, slot);
              case 'new':
                await PuzzleActions.newPuzzle(context, c, slot);
              case 'prev':
                await PuzzleActions.previous(context, c, slot);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('Büyüt ve oyna')),
            PopupMenuItem(value: 'check', child: Text('Kontrol')),
            PopupMenuItem(value: 'hint', child: Text('İpucu')),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'reset',
              child: Text('Baştan başlat (sıfırla)'),
            ),
            PopupMenuItem(value: 'new', child: Text('Yeni bulmaca getir')),
            PopupMenuItem(value: 'prev', child: Text('Önceki denemeler')),
          ],
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.session, required this.showTimer});
  final AttemptSession session;
  final bool showTimer;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final p = session.game.progress;
    final pct = (p * 100).round();
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Doldurulan hücre oranı yüzde $pct',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                value: p,
                minHeight: 4,
                color: pal.ink,
                backgroundColor: pal.rule.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('%$pct dolu', style: sansStyle(pal.inkSoft, 13)),
        if (showTimer) ...[
          const SizedBox(width: 10),
          Icon(Icons.schedule, size: 14, color: pal.inkSoft),
          const SizedBox(width: 3),
          Text(
            formatDuration(session.elapsedMs),
            style: sansStyle(pal.inkSoft, 13),
          ),
        ],
        if (session.game.hintCount > 0) ...[
          const SizedBox(width: 10),
          Icon(Icons.lightbulb_outline, size: 14, color: pal.inkSoft),
          Text('${session.game.hintCount}', style: sansStyle(pal.inkSoft, 13)),
        ],
      ],
    );
  }
}

/// Baskı damgası. Renk + metin + çerçeve; yalnızca renge dayanmaz.
class _Stamp extends StatelessWidget {
  const _Stamp(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.pal.ok;
    return Transform.rotate(
      angle: -0.2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: c.withValues(alpha: 0.8), width: 3),
          borderRadius: BorderRadius.circular(3),
          color: context.pal.paper.withValues(alpha: 0.55),
        ),
        child: Text(
          text,
          style: serifStyle(c.withValues(alpha: 0.9), 26, ls: 3),
        ),
      ),
    );
  }
}

class PageStamp extends StatelessWidget {
  const PageStamp({super.key});
  @override
  Widget build(BuildContext context) => const _Stamp('TAMAMLANDI');
}

class _Problem extends ConsumerWidget {
  const _Problem({required this.slot, this.reason});
  final PuzzleSlot slot;
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(appControllerProvider);
    final pal = context.pal;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: pal.bad, width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_gmailerrorred, color: pal.bad),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bu bulmacanın kaydı okunamadı',
                  style: serifStyle(pal.ink, 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bozuk kayıt silinmedi; cihazda ayrı bir klasöre alındı. Bu yuvaya yeni bir '
            'bulmaca getirebilirsiniz; sayfadaki diğer bulmaca etkilenmez.'
            '${reason == null ? '' : '\n\nAyrıntı: $reason'}',
            style: sansStyle(pal.ink, 14, h: 1.4),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () async {
              final ok = await PuzzleActions.confirm(
                context,
                title: 'Yeni bulmaca ile devam?',
                body:
                    'Okunamayan kayıt yerine bu yuvaya yeni bir bulmaca gelecek.',
                action: 'Devam et',
              );
              if (ok == true) await c.recoverSlot(slot);
            },
            child: const Text('Yeni bulmaca ile devam et'),
          ),
        ],
      ),
    );
  }
}
