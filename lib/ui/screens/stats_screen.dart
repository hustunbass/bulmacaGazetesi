import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/attempt.dart';
import '../../domain/puzzle.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/paper.dart';

/// Sakin bir özet: tamamlanan sayılar ve yalnızca yardımsız çözümlerin süreleri.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final pal = context.pal;
    final records = c.completions;
    return Scaffold(
      appBar: AppBar(title: const Text('İstatistikler')),
      body: PaperTextureOverlay(
        child: SafeArea(
          child: records.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Semantics(
                      container: true,
                      child: Text(
                        'Henüz tamamlanmış bulmaca yok. Bir bulmacayı bitirdiğinizde '
                        'burada sessizce görünecek.',
                        textAlign: TextAlign.center,
                        style: sansStyle(pal.inkSoft, 17, h: 1.4),
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Semantics(
                      container: true,
                      label: 'Toplam tamamlanan bulmaca: ${records.length}',
                      child: ExcludeSemantics(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: 12,
                          children: [
                            Text(
                              '${records.length}',
                              style: serifStyle(pal.ink, 44),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'tamamlanan bulmaca',
                                style: sansStyle(pal.inkSoft, 17),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const NewsRule(heavy: true),
                    for (final t in PuzzleType.values)
                      if (records.any((r) => r.type == t))
                        _TypeSection(
                          type: t,
                          records: [
                            for (final r in records)
                              if (r.type == t) r,
                          ],
                        ),
                    const SizedBox(height: 16),
                    const NewsRule(),
                    const SizedBox(height: 12),
                    Text(
                      'Süreler yalnızca ipucu kullanılmadan çözülen bulmacalardan '
                      'hesaplanır; yardımlı çözümler sayıya katılır ama sürelere '
                      'katılmaz. Süreler yalnızca aynı tür ve zorluk içinde '
                      'karşılaştırılabilir.',
                      style: sansStyle(pal.inkSoft, 15, h: 1.4),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  const _TypeSection({required this.type, required this.records});
  final PuzzleType type;
  final List<CompletionRecord> records;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final assisted = records.where((r) => r.assisted).length;
    final unassisted = records.length - assisted;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type.label, style: serifStyle(pal.ink, 22)),
          const SizedBox(height: 4),
          Text(
            '${records.length} tamamlandı · $unassisted yardımsız · $assisted yardımlı',
            style: sansStyle(pal.inkSoft, 16),
          ),
          const SizedBox(height: 8),
          for (final d in Difficulty.values)
            if (records.any((r) => r.difficulty == d))
              _DifficultyRow(
                type: type,
                difficulty: d,
                records: [
                  for (final r in records)
                    if (r.difficulty == d) r,
                ],
              ),
        ],
      ),
    );
  }
}

class _DifficultyRow extends StatelessWidget {
  const _DifficultyRow({
    required this.type,
    required this.difficulty,
    required this.records,
  });
  final PuzzleType type;
  final Difficulty difficulty;
  final List<CompletionRecord> records;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final times = [
      for (final r in records)
        if (!r.assisted) r.elapsedMs,
    ];
    final String detail;
    if (times.isEmpty) {
      detail = 'Yardımsız süre yok (${records.length} yardımlı)';
    } else {
      final best = times.reduce((a, b) => a < b ? a : b);
      final avg = times.reduce((a, b) => a + b) ~/ times.length;
      detail =
          'En iyi ${formatDuration(best)} · Ortalama ${formatDuration(avg)} '
          '(${times.length} yardımsız)';
    }
    return Semantics(
      container: true,
      label: '${type.label}, ${difficulty.label}: $detail',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: pal.rule, width: 0.7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  difficulty.label,
                  style: sansStyle(pal.ink, 16, w: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Text(detail, style: sansStyle(pal.ink, 16, h: 1.3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
