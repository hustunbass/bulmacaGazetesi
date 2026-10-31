import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/newspaper.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../tr_date.dart';
import 'paper.dart';
import 'puzzle_card.dart';

/// Gazetenin tek sayfası: manşet, iki bulmaca, ince ayırıcı. Geniş ekranda
/// iki bulmaca yan yana, gazete sütunu gibi dizilir.
class NewspaperPageView extends ConsumerWidget {
  const NewspaperPageView({
    super.key,
    required this.issue,
    required this.page,
    required this.pageCount,
    required this.onMenu,
    required this.onPicker,
  });

  final NewspaperIssue issue;
  final NewspaperPage page;
  final int pageCount;
  final VoidCallback onMenu;
  final VoidCallback onPicker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final pal = context.pal;
    final allDone = page.slots.every(
      (s) => c.sessionFor(s)?.meta.completed ?? false,
    );
    return PaperSheet(
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 720;
          final cards = [
            for (final s in page.slots)
              PuzzleCard(key: ValueKey(s.attemptId), slot: s),
          ];
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 10, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Masthead(
                  issue: issue,
                  page: page.index + 1,
                  onMenu: onMenu,
                  onPicker: onPicker,
                ),
                const SizedBox(height: 8),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(left: 14),
                          padding: const EdgeInsets.only(left: 14),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: pal.ink.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                          child: cards[1],
                        ),
                      ),
                    ],
                  )
                else ...[
                  cards[0],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: NewsRule(),
                  ),
                  cards[1],
                ],
                if (allDone)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Center(
                      child: Opacity(opacity: 0.9, child: const PageStamp()),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Sayfa ${page.index + 1} / $pageCount',
                  textAlign: TextAlign.center,
                  style: sansStyle(pal.inkSoft, 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.issue,
    required this.page,
    required this.onMenu,
    required this.onPicker,
  });
  final NewspaperIssue issue;
  final int page;
  final VoidCallback onMenu;
  final VoidCallback onPicker;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Sayfa seçici',
              icon: const Icon(Icons.grid_view),
              onPressed: onPicker,
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Bulmaca Gazetesi',
                    textAlign: TextAlign.center,
                    style: serifStyle(pal.ink, 30, w: FontWeight.w800),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Menü: arşiv, istatistikler, ayarlar',
              icon: const Icon(Icons.menu),
              onPressed: onMenu,
            ),
          ],
        ),
        const NewsRule(heavy: true),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 2,
            children: [
              Text(
                '${issue.number}. SAYI',
                style: sansStyle(pal.ink, 12, w: FontWeight.w800, ls: 1),
              ),
              Text(
                'BULMACA EKİ',
                style: sansStyle(pal.accent, 12, w: FontWeight.w800, ls: 1.4),
              ),
              Text(
                trDate(issue.date),
                style: sansStyle(pal.ink, 12, w: FontWeight.w700),
              ),
            ],
          ),
        ),
        const NewsRule(),
      ],
    );
  }
}
