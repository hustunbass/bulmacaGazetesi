import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/attempt.dart';
import '../../domain/newspaper.dart';
import '../../domain/puzzle.dart';
import '../../state/app_controller.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/paper.dart';

const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
const _days = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

String _dateText(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}, ${_days[d.weekday - 1]}';

enum _Status {
  all('Tümü'),
  notStarted('Başlanmamış'),
  inProgress('Devam eden'),
  done('Tamamlanmış');

  const _Status(this.label);
  final String label;
}

/// Geçmiş sayılar. Özetler satırlar görünür oldukça tembel yüklenir.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key, required this.onOpenIssue});
  final Future<void> Function(String issueId) onOpenIssue;

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  List<String>? _ids;
  String? _loadError;
  final Map<String, IssueSummary?> _cache = {};
  final Map<String, Future<IssueSummary?>> _futures = {};
  _Status _status = _Status.all;
  PuzzleType? _type;
  Difficulty? _difficulty;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _loadIds();
  }

  Future<void> _loadIds() async {
    try {
      final ids = await ref.read(appControllerProvider).issueIds();
      if (!mounted) return;
      setState(() => _ids = ids);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Arşiv okunamadı: $e');
    }
  }

  Future<IssueSummary?> _summary(String id) {
    return _futures.putIfAbsent(id, () async {
      IssueSummary? r;
      try {
        r = await ref.read(appControllerProvider).summarize(id);
      } on Object {
        r = null;
      }
      _cache[id] = r;
      if (mounted && _filtering) setState(() {});
      return r;
    });
  }

  bool get _filtering =>
      _status != _Status.all || _type != null || _difficulty != null;

  bool _passes(String id) {
    final s = _cache[id];
    if (s == null) return true; // yüklenmemiş satırlar listede kalır
    switch (_status) {
      case _Status.all:
        break;
      case _Status.notStarted:
        if (!s.notStarted) {
          return false;
        }
      case _Status.inProgress:
        if (s.inProgress == 0 && !(s.completed > 0 && !s.isComplete)) {
          return false;
        }
      case _Status.done:
        if (!s.isComplete) {
          return false;
        }
    }
    if (_type != null && !s.types.contains(_type)) {
      return false;
    }
    if (_difficulty != null && !s.difficulties.contains(_difficulty)) {
      return false;
    }
    return true;
  }

  Future<void> _open(String id) async {
    if (_opening) return;
    _opening = true;
    try {
      await widget.onOpenIssue(id);
      if (mounted) Navigator.of(context).pop();
    } finally {
      _opening = false;
    }
  }

  Future<void> _resume() async {
    final ids = _ids ?? const [];
    for (final id in ids) {
      final s = await _summary(id);
      if (!mounted) return;
      if (s != null && s.inProgress > 0) {
        await _open(id);
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Devam eden sayı bulunamadı.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appControllerProvider);
    final pal = context.pal;
    final ids = _ids;
    final shown = ids == null ? const <String>[] : ids.where(_passes).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Arşiv')),
      body: PaperTextureOverlay(
        child: SafeArea(
          child: _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_loadError!, style: sansStyle(pal.ink, 17)),
                  ),
                )
              : ids == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: shown.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) return _filters(context);
                    if (i == 1 && shown.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          ids.isEmpty
                              ? 'Arşivde henüz sayı yok.'
                              : 'Bu süzgece uyan sayı yok.',
                          style: sansStyle(pal.inkSoft, 17),
                        ),
                      );
                    }
                    if (i == 1) return const SizedBox.shrink();
                    final id = shown[i - 2];
                    return _IssueRow(
                      key: ValueKey(id),
                      id: id,
                      future: _summary(id),
                      current: c.issue?.id == id,
                      onOpen: () => _open(id),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final pal = context.pal;
    Widget chip(String label, bool sel, VoidCallback onTap) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Center(
        child: FilterChip(
          label: Text(label),
          selected: sel,
          showCheckmark: true,
          onSelected: (_) => onTap(),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          labelStyle: sansStyle(pal.ink, 15, w: FontWeight.w600),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Kaldığım yerden devam et'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in _Status.values)
                chip(s.label, _status == s, () => setState(() => _status = s)),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final t in PuzzleType.values)
                chip(
                  t.shortLabel,
                  _type == t,
                  () => setState(() => _type = _type == t ? null : t),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final d in Difficulty.values)
                chip(
                  d.label,
                  _difficulty == d,
                  () =>
                      setState(() => _difficulty = _difficulty == d ? null : d),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const NewsRule(heavy: true),
        ],
      ),
    );
  }
}

class _IssueRow extends ConsumerStatefulWidget {
  const _IssueRow({
    super.key,
    required this.id,
    required this.future,
    required this.current,
    required this.onOpen,
  });
  final String id;
  final Future<IssueSummary?> future;
  final bool current;
  final VoidCallback onOpen;

  @override
  ConsumerState<_IssueRow> createState() => _IssueRowState();
}

class _IssueRowState extends ConsumerState<_IssueRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return FutureBuilder<IssueSummary?>(
      future: widget.future,
      builder: (context, snap) {
        final s = snap.data;
        final date = s?.issue.date ?? NewspaperIssue.parseIssueDate(widget.id);
        // Özet yüklenene dek numara bilinmez; numara kurulum gününe göre hesaplanır.
        final number = s?.issue.number.toString() ?? '…';
        final (IconData icon, String status) = s == null
            ? (
                Icons.hourglass_empty,
                snap.connectionState == ConnectionState.done
                    ? 'Okunamadı'
                    : 'Yükleniyor',
              )
            : s.isComplete
            ? (Icons.check_circle_outline, 'Tamamlandı')
            : s.notStarted
            ? (Icons.radio_button_unchecked, 'Başlanmadı')
            : (Icons.timelapse, 'Devam ediyor');
        final progress = s == null ? '' : ' (${s.completed}/${s.total})';
        final types = s == null
            ? ''
            : [
                for (final t in PuzzleType.values)
                  if (s.types.contains(t)) t.shortLabel,
              ].join(', ');
        final hasHistory =
            s != null && s.issue.slots.any((x) => x.history.isNotEmpty);
        final label =
            '${_dateText(date)}, $number. Sayı, $status$progress'
            '${types.isEmpty ? '' : ', $types'}'
            '${widget.current ? ', şu an açık' : ''}';
        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: pal.rule, width: 0.7)),
            color: widget.current ? pal.paperDeep : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: label,
                      excludeSemantics: true,
                      onTap: widget.onOpen,
                      child: InkWell(
                        onTap: widget.onOpen,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 64),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                            child: Row(
                              children: [
                                Icon(icon, color: pal.ink),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _dateText(date),
                                        style: serifStyle(pal.ink, 17),
                                      ),
                                      Text(
                                        '$number. Sayı · $status$progress'
                                        '${widget.current ? ' · Açık' : ''}',
                                        style: sansStyle(pal.ink, 15),
                                      ),
                                      if (types.isNotEmpty)
                                        Text(
                                          types,
                                          style: sansStyle(
                                            pal.inkSoft,
                                            14,
                                            w: FontWeight.w400,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (hasHistory)
                    IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      tooltip: _expanded
                          ? 'Değiştirilen bulmacaları gizle'
                          : 'Değiştirilen bulmacaları göster',
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                ],
              ),
              if (_expanded && s != null) _History(summary: s),
            ],
          ),
        );
      },
    );
  }
}

class _History extends ConsumerStatefulWidget {
  const _History({required this.summary});
  final IssueSummary summary;
  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  late final Future<List<AttemptMeta>> _future = _load();

  Future<List<AttemptMeta>> _load() async {
    final c = ref.read(appControllerProvider);
    final out = <AttemptMeta>[];
    for (final slot in widget.summary.issue.slots) {
      if (slot.history.isEmpty) continue;
      out.addAll(await c.previousAttempts(slot));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final lib = ref.read(appControllerProvider).library;
    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
      child: FutureBuilder<List<AttemptMeta>>(
        future: _future,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) {
            return Text('Yükleniyor', style: sansStyle(pal.inkSoft, 14));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Değiştirilen bulmacalar',
                  style: serifStyle(pal.ink, 16),
                ),
              ),
              for (final m in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${lib.byId(m.puzzleId)?.title ?? m.puzzleId} · '
                    '${m.completed
                        ? 'Tamamlandı'
                        : m.touched
                        ? 'Yarım kaldı'
                        : 'Başlanmadı'}'
                    ' · ${formatDuration(m.elapsedMs)}',
                    style: sansStyle(pal.ink, 15, w: FontWeight.w400),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
