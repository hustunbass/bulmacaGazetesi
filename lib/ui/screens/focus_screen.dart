import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/newspaper.dart';
import '../../domain/puzzle.dart';
import '../../domain/word_game.dart';
import '../../state/app_controller.dart';
import '../../state/attempt_session.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../puzzle_actions.dart';
import '../theme.dart';
import '../widgets/keyboards.dart';
import '../widgets/sudoku_grid.dart';
import '../widgets/word_grid.dart';

/// Bulmaca odak modu: sayfadaki oyunun *aynı* durumunun büyütülmüş görünümü.
/// Yeni bir bulmaca ya da durum kopyası oluşturmaz.
class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key, required this.slot, this.initialCell});
  final PuzzleSlot slot;
  final int? initialCell;

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  final _focus = FocusNode(debugLabel: 'focus-keys');
  final _tc = TransformationController();
  Timer? _clock;
  bool _showingCompletion = false;
  AppController? _ctl;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = _session;
      if (s == null) return;
      s.activate();
      final cell = widget.initialCell;
      if (cell != null) _selectCell(s, cell);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _focus.dispose();
    _tc.dispose();
    // Odak modundan çıkınca süre durur; sayfa konumu ve seçim korunur.
    _ctl?.pauseAll();
    super.dispose();
  }

  AttemptSession? get _session {
    final AppController c = _ctl ?? ref.read(appControllerProvider);
    return c.sessionFor(widget.slot);
  }

  void _selectCell(AttemptSession s, int cell) {
    s.activate();
    final w = s.word;
    if (w != null) {
      s.mutate(() => w.tapCell(cell), edit: false);
    } else {
      s.mutate(() => s.sudoku!.select(cell), edit: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appControllerProvider);
    _ctl = c;
    final s = c.sessionFor(widget.slot);
    final pal = context.pal;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            'Bu bulmaca artık açık değil.',
            style: sansStyle(pal.ink, 16),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.justCompleted && !_showingCompletion) {
          _showingCompletion = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            s.consumeCompletion();
            if (c.settings.haptics) HapticFeedback.mediumImpact();
            await _showCompletion(c, s);
            _showingCompletion = false;
          });
        }
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (node, e) => _onKey(c, s, e),
          child: Scaffold(
            appBar: _appBar(c, s),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(child: _body(c, s)),
                  // Küçük ekranlarda bulmaca alanını yemesin diye banner yalnızca
                  // yeterince yüksek ekranlarda gösterilir.
                  if (MediaQuery.sizeOf(context).height >= 700)
                    Center(child: c.ads.banner()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ üst bar

  PreferredSizeWidget _appBar(AppController c, AttemptSession s) {
    final pal = context.pal;
    return AppBar(
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.def.title,
            style: serifStyle(pal.ink, 18),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${s.def.type.shortLabel} · ${s.def.difficulty.label}'
            '${c.settings.showTimer ? ' · ${formatDuration(s.elapsedMs)}' : ''}',
            style: sansStyle(pal.inkSoft, 13),
          ),
        ],
      ),
      actions: [
        if (s.word != null)
          IconButton(
            tooltip: 'Soru listesi',
            icon: const Icon(Icons.format_list_numbered),
            onPressed: () => _showClueList(s),
          ),
        if (s.word != null)
          IconButton(
            tooltip: 'Yakınlaştır / uzaklaştır',
            icon: const Icon(Icons.zoom_in_map),
            onPressed: _toggleZoom,
          ),
        PopupMenuButton<String>(
          tooltip: 'Bulmaca menüsü',
          onSelected: (v) async {
            switch (v) {
              case 'reset':
                await PuzzleActions.reset(context, c, widget.slot);
              case 'new':
                await PuzzleActions.newPuzzle(context, c, widget.slot);
              case 'prev':
                await PuzzleActions.previous(context, c, widget.slot);
            }
          },
          itemBuilder: (_) => const [
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

  void _toggleZoom() {
    final cur = _tc.value.getMaxScaleOnAxis();
    _tc.value = cur > 1.2
        ? Matrix4.identity()
        : Matrix4.diagonal3Values(2, 2, 1);
  }

  // -------------------------------------------------------------------- gövde

  Widget _body(AppController c, AttemptSession s) {
    return LayoutBuilder(
      builder: (context, box) {
        // Tablette klavye alta, tam genişlikte ve daha büyük tuşlarla yerleşir.
        final big = box.maxWidth >= 600;
        final grid = _grid(c, s);
        final panel = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.word != null) _clueBar(s),
            if (s.meta.completed) _reviewBanner(),
            _tools(c, s),
            if (s.word != null)
              TurkishKeyboard(
                keyHeight: big ? 64 : 46,
                fontSize: big ? 26 : 19,
                haptics: c.settings.haptics,
                onLetter: (l) => _input(s, l),
                onBackspace: () => _backspace(s),
              )
            else
              NumberPad(
                keyHeight: big ? 72 : 54,
                fontSize: big ? 32 : 24,
                game: s.sudoku!,
                haptics: c.settings.haptics,
                onDigit: (d) => _digit(c, s, d),
              ),
          ],
        );
        // Küçük ekran + büyük yazıda panel, ızgaranın yerini yemesin: panel
        // en çok yüksekliğin %62'sini alır, sığmazsa kendi içinde kayar.
        return Column(
          children: [
            Expanded(child: grid),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: box.maxHeight * 0.62),
              child: SingleChildScrollView(child: panel),
            ),
          ],
        );
      },
    );
  }

  Widget _reviewBanner() {
    final pal = context.pal;
    return Container(
      width: double.infinity,
      color: pal.hintFill,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: pal.ok),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tamamlandı — inceleme modu. Yeniden çözmek için menüden “Baştan başlat”ı kullanın.',
              style: sansStyle(pal.ink, 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(AppController c, AttemptSession s) {
    return LayoutBuilder(
      builder: (context, box) {
        final pad = const EdgeInsets.all(8);
        final w = box.maxWidth - pad.horizontal;
        final h = box.maxHeight - pad.vertical;
        if (s.sudoku != null) {
          return Padding(
            padding: pad,
            child: SudokuGridView(
              session: s,
              showConflicts: c.settings.sudokuShowConflicts,
              onCellTap: (i) => _selectCell(s, i),
            ),
          );
        }
        final g = s.word!;
        final view = SizedBox(
          width: w,
          height: h,
          child: WordGridView(
            session: s,
            showWrong: c.settings.highlightErrors,
            live: c.settings.liveFeedback,
            onCellTap: (i) {
              _selectCell(s, i);
              _ensureVisible(g, w, h);
            },
            onClueTap: (i) => _showClueCell(s, i),
          ),
        );
        return Padding(
          padding: pad,
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 4,
            child: view,
          ),
        );
      },
    );
  }

  /// Seçili hücre yakınlaştırılmış görünümde ekran dışında kalırsa kaydırır.
  void _ensureVisible(WordGame g, double vw, double vh) {
    final scale = _tc.value.getMaxScaleOnAxis();
    if (scale <= 1.01 || g.selCell < 0) return;
    final s = g.structure;
    final cell = min(vw / s.cols, vh / s.rows);
    final ox = (vw - cell * s.cols) / 2, oy = (vh - cell * s.rows) / 2;
    final r = g.selCell ~/ s.cols, c = g.selCell % s.cols;
    final p = MatrixUtils.transformPoint(
      _tc.value,
      Offset(ox + (c + 0.5) * cell, oy + (r + 0.5) * cell),
    );
    var dx = 0.0, dy = 0.0;
    final m = cell * scale;
    if (p.dx < m) dx = m - p.dx;
    if (p.dx > vw - m) dx = vw - m - p.dx;
    if (p.dy < m) dy = m - p.dy;
    if (p.dy > vh - m) dy = vh - m - p.dy;
    if (dx != 0 || dy != 0) {
      _tc.value = Matrix4.translationValues(dx, dy, 0) * _tc.value;
    }
  }

  // --------------------------------------------------------------- soru çubuğu

  Widget _clueBar(AttemptSession s) {
    final pal = context.pal;
    final g = s.word!;
    final k = g.activeEntry;
    final e = k == null ? null : g.structure.entries[k];
    return Material(
      color: pal.paperDeep,
      child: InkWell(
        onTap: () => _showClueList(s),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          decoration: BoxDecoration(
            border: Border.symmetric(horizontal: BorderSide(color: pal.rule)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Önceki soru',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => s.mutate(() => g.stepEntry(-1), edit: false),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: e == null
                      ? Text(
                          'Bir hücre seçin veya soruya dokunun.',
                          textAlign: TextAlign.center,
                          style: sansStyle(pal.inkSoft, 16),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${e.number > 0 ? '${e.number}. ' : ''}${e.dir.label} · ${e.length} harf'
                              '${e.category.isNotEmpty && s.def.type == PuzzleType.klasik ? ' · ${e.category}' : ''}',
                              style: sansStyle(
                                pal.accent,
                                13,
                                w: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              e.clue,
                              textAlign: TextAlign.center,
                              style: serifStyle(
                                pal.ink,
                                17,
                                w: FontWeight.w600,
                                h: 1.2,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              IconButton(
                tooltip: 'Sonraki soru',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => s.mutate(() => g.stepEntry(1), edit: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Çengel: soru hücresine dokununca büyütülmüş panel. Birden fazla yön varsa
  /// her yönün ipucu ayrı ayrı gösterilir.
  Future<void> _showClueCell(AttemptSession s, int cell) async {
    final g = s.word!;
    final entries = g.structure.clueCells[cell] ?? const <int>[];
    final k = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Soru', style: serifStyle(ctx.pal.ink, 20)),
              const SizedBox(height: 10),
              for (final k in entries) ...[
                Text(
                  '${g.structure.entries[k].dir.label} · ${g.structure.entries[k].length} harf',
                  style: sansStyle(ctx.pal.accent, 14, w: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  g.structure.entries[k].clue,
                  style: serifStyle(
                    ctx.pal.ink,
                    20,
                    w: FontWeight.w600,
                    h: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, k),
                    child: const Text('Bu cevaba git'),
                  ),
                ),
                if (k != entries.last) const Divider(height: 28),
              ],
            ],
          ),
        ),
      ),
    );
    if (k != null) {
      s.activate();
      s.mutate(() => g.selectEntry(k), edit: false);
    }
  }

  /// Tam soru listesi. Klasikte kategori etiketi gösterilir; panel açılınca
  /// aktif soruya kaydırılır.
  Future<void> _showClueList(AttemptSession s) async {
    final g = s.word!;
    final st = g.structure;
    final order = [for (var i = 0; i < st.entries.length; i++) i];
    if (s.def.type == PuzzleType.cengel) {
      order.sort((a, b) {
        final ea = st.entries[a], eb = st.entries[b];
        return ea.clueRow != eb.clueRow
            ? ea.clueRow - eb.clueRow
            : ea.clueCol - eb.clueCol;
      });
    } else {
      order.sort((a, b) {
        final ea = st.entries[a], eb = st.entries[b];
        if (ea.dir != eb.dir) return ea.dir == Dir.across ? -1 : 1;
        return ea.number - eb.number;
      });
    }
    final active = g.activeEntry;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final pal = ctx.pal;
        final double initial = active == null
            ? 0.0
            : max(0, order.indexOf(active) - 1) * 64.0;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (ctx, sc) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sc.hasClients && sc.offset == 0) {
                sc.jumpTo(min<double>(initial, sc.position.maxScrollExtent));
              }
            });
            return ListView.builder(
              controller: sc,
              itemCount: order.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text('Sorular', style: serifStyle(pal.ink, 22)),
                  );
                }
                final k = order[i - 1];
                final e = st.entries[k];
                final prevDir = i > 1 ? st.entries[order[i - 2]].dir : null;
                final isActive = k == active;
                final tile = ListTile(
                  selected: isActive,
                  selectedTileColor: pal.selection.withValues(alpha: 0.5),
                  minVerticalPadding: 8,
                  leading: SizedBox(
                    width: 34,
                    child: Text(
                      e.number > 0
                          ? '${e.number}.'
                          : (e.dir == Dir.across ? '→' : '↓'),
                      style: serifStyle(pal.accent, 17),
                    ),
                  ),
                  title: Text(
                    e.clue,
                    style: sansStyle(pal.ink, 16, w: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${e.length} harf'
                    '${e.category.isNotEmpty && s.def.type == PuzzleType.klasik ? ' · ${e.category}' : ''}'
                    '${s.def.type == PuzzleType.cengel ? ' · ${e.dir.label}' : ''}',
                  ),
                  trailing: isActive ? const Icon(Icons.edit_outlined) : null,
                  onTap: () => Navigator.pop(ctx, k),
                );
                if (s.def.type != PuzzleType.cengel && prevDir != e.dir) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                        child: Text(
                          e.dir.label.toUpperCase(),
                          style: sansStyle(
                            pal.inkSoft,
                            13,
                            w: FontWeight.w800,
                            ls: 1.2,
                          ),
                        ),
                      ),
                      const NewsRuleLine(),
                      tile,
                    ],
                  );
                }
                return tile;
              },
            );
          },
        );
      },
    );
    if (picked != null) {
      s.activate();
      s.mutate(() => g.selectEntry(picked), edit: false);
    }
  }

  // ------------------------------------------------------------------ araçlar

  Widget _tools(AppController c, AttemptSession s) {
    final w = s.word;
    final g = s.game;
    final items = <Widget>[];
    if (w != null) {
      items.addAll([
        _ToolButton(
          icon: Icons.rule,
          label: 'Kontrol',
          onTap: () => PuzzleActions.check(context, c, s),
        ),
        _ToolButton(
          icon: Icons.lightbulb_outline,
          label: 'İpucu',
          onTap: () => PuzzleActions.hint(context, c, s),
        ),
        _EraseButton(
          onCell: () => _backspaceCell(s),
          onEntry: () => _edit(s, () => w.clearEntry(), erase: true),
        ),
      ]);
    } else {
      final su = s.sudoku!;
      items.addAll([
        _ToolButton(
          icon: Icons.edit_note,
          label: 'Not',
          active: su.noteMode,
          onTap: () => s.mutate(() => su.toggleNoteMode(), edit: false),
        ),
        _ToolButton(
          icon: Icons.backspace_outlined,
          label: 'Sil',
          onTap: () => _edit(s, () => su.erase(), erase: true),
        ),
        _ToolButton(
          icon: Icons.lightbulb_outline,
          label: 'İpucu',
          onTap: () => PuzzleActions.hint(context, c, s),
        ),
        _ToolButton(
          icon: Icons.rule,
          label: 'Kontrol',
          onTap: () => PuzzleActions.check(context, c, s),
        ),
      ]);
    }
    items.addAll([
      _ToolButton(
        icon: Icons.undo,
        label: 'Geri al',
        onTap: g.canUndo ? () => _undo(s) : null,
      ),
      _ToolButton(
        icon: Icons.redo,
        label: 'Yinele',
        onTap: g.canRedo ? () => _redo(s) : null,
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(children: [for (final i in items) Expanded(child: i)]),
    );
  }

  void _undo(AttemptSession s) {
    s.activate();
    s.mutate(() {
      final w = s.word;
      w != null ? w.undo() : s.sudoku!.undo();
    });
  }

  void _redo(AttemptSession s) {
    s.activate();
    s.mutate(() {
      final w = s.word;
      w != null ? w.redo() : s.sudoku!.redo();
    });
  }

  /// Oyun durumunu değiştirir; yalnızca durum gerçekten değiştiyse ses çalar
  /// (yazma: kalem hışırtısı, silme: silgi).
  void _edit(AttemptSession s, void Function() change, {bool erase = false}) {
    String sig() => s.word != null
        ? s.word!.letters.join()
        : '${s.sudoku!.values.join()}|${s.sudoku!.notes.join(',')}';
    final before = sig();
    s.activate();
    s.mutate(change);
    if (sig() != before) {
      erase ? _ctl?.sfxErase() : _ctl?.sfxPen();
    }
  }

  void _input(AttemptSession s, String l) =>
      _edit(s, () => s.word!.inputLetter(l));

  void _backspace(AttemptSession s) =>
      _edit(s, () => s.word!.backspace(), erase: true);

  void _backspaceCell(AttemptSession s) {
    final w = s.word!;
    _edit(s, () {
      final c = w.selCell;
      if (c >= 0 && w.letters[c].isNotEmpty && !w.hinted[c]) w.backspace();
    }, erase: true);
  }

  void _digit(AppController c, AttemptSession s, int d) => _edit(
    s,
    () => s.sudoku!.inputDigit(d, autoClear: c.settings.sudokuAutoClear),
  );

  // --------------------------------------------------------- fiziksel klavye

  KeyEventResult _onKey(AppController c, AttemptSession s, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final w = s.word;
    final su = s.sudoku;
    int dr = 0, dc = 0;
    if (k == LogicalKeyboardKey.arrowLeft) dc = -1;
    if (k == LogicalKeyboardKey.arrowRight) dc = 1;
    if (k == LogicalKeyboardKey.arrowUp) dr = -1;
    if (k == LogicalKeyboardKey.arrowDown) dr = 1;
    if (dr != 0 || dc != 0) {
      s.activate();
      s.mutate(
        () => w != null ? w.moveSelection(dr, dc) : su!.moveSelection(dr, dc),
        edit: false,
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      if (w != null) {
        _backspace(s);
      } else {
        _edit(s, () => su!.erase(), erase: true);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      if (w != null) {
        _backspaceCell(s);
      } else {
        _edit(s, () => su!.erase(), erase: true);
      }
      return KeyEventResult.handled;
    }
    if (w != null && k == LogicalKeyboardKey.tab) {
      final back = HardwareKeyboard.instance.isShiftPressed;
      s.mutate(() => w.stepEntry(back ? -1 : 1), edit: false);
      return KeyEventResult.handled;
    }
    if (w != null && k == LogicalKeyboardKey.space) {
      if (w.selCell >= 0) {
        s.mutate(() => w.tapCell(w.selCell), edit: false);
      }
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch == null || ch.isEmpty) return KeyEventResult.ignored;
    if (w != null) {
      final before = w.letters.join();
      _input(s, ch);
      return before == w.letters.join() && w.selCell < 0
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }
    final d = int.tryParse(ch);
    if (su != null && d != null && d >= 1 && d <= 9) {
      _digit(c, s, d);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------- tamamlama

  Future<void> _showCompletion(AppController c, AttemptSession s) async {
    if (!mounted) return;
    final pal = context.pal;
    final act = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: pal.ok),
            const SizedBox(width: 10),
            const Expanded(child: Text('Bulmaca tamamlandı')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.def.title,
              style: serifStyle(pal.ink, 18, w: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _statRow('Süre', formatDuration(s.elapsedMs)),
            _statRow('İpucu', '${s.game.hintCount}'),
            _statRow('Tamamlama', s.assisted ? 'Yardımlı' : 'Yardımsız'),
            if (s.game.checkCount > 0)
              _statRow('Kontrol', '${s.game.checkCount}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'review'),
            child: const Text('İncele'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'new'),
            child: const Text('Yeni bulmaca'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'page'),
            child: const Text('Sayfaya dön'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (act == 'page') {
      Navigator.of(context).pop();
    } else if (act == 'new') {
      await PuzzleActions.newPuzzle(context, c, widget.slot);
    }
  }

  Widget _statRow(String k, String v) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(k, style: sansStyle(pal.inkSoft, 15))),
          Text(v, style: sansStyle(pal.ink, 16, w: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final enabled = onTap != null;
    final color = enabled ? pal.ink : pal.rule;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: active,
      label: active ? '$label, açık' : label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(
            border: active
                ? Border(bottom: BorderSide(color: pal.accent, width: 3))
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: active ? pal.accent : color),
              const SizedBox(height: 2),
              Text(
                label,
                style: sansStyle(
                  active ? pal.accent : color,
                  12,
                  w: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sil: dokununca seçili hücreyi, basılı tutunca/menüden seçili cevabı siler.
class _EraseButton extends StatelessWidget {
  const _EraseButton({required this.onCell, required this.onEntry});
  final VoidCallback onCell;
  final VoidCallback onEntry;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return PopupMenuButton<String>(
      tooltip: 'Sil',
      onSelected: (v) => v == 'cell' ? onCell() : onEntry(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'cell', child: Text('Seçili hücreyi sil')),
        PopupMenuItem(value: 'entry', child: Text('Seçili cevabı temizle')),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.backspace_outlined, size: 22, color: pal.ink),
            const SizedBox(height: 2),
            Text('Sil', style: sansStyle(pal.ink, 12, w: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class NewsRuleLine extends StatelessWidget {
  const NewsRuleLine({super.key});
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: context.pal.ink.withValues(alpha: 0.5),
  );
}
