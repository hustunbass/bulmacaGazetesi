import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/newspaper.dart';
import '../state/app_controller.dart';
import '../state/providers.dart';
import 'screens/archive_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'theme.dart';
import 'tr_date.dart';
import 'widgets/newspaper_page_view.dart';
import 'widgets/page_turner.dart';

/// Ana yüzey: gazete sayfaları. Sayfa çevirme, alt kontroller, yaşam döngüsü
/// (arka plana geçerken kayıt + süre durdurma) ve genel menüler burada.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  late final PageTurnerController _pages;
  bool _noticesShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final c = ref.read(appControllerProvider);
    final count = c.issue?.pages.length ?? 1;
    _pages = PageTurnerController(
      initial: c.settings.lastPage.clamp(0, count - 1),
    );
    _pages.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!c.settings.onboardingDone) _showOnboarding(c);
      _showNotices(c);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = ref.read(appControllerProvider);
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        c.onBackground();
      case AppLifecycleState.resumed:
        c.onResume();
        // Reklam ilk açılışta (ör. ağ yokken) başlamadıysa yeniden dener.
        c.ads.init();
    }
  }

  void _showOnboarding(AppController c) {
    c.pauseAll();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => OnboardingScreen(
          onDone: () {
            c.updateSettings(c.settings.copyWith(onboardingDone: true));
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  Future<void> _showNotices(AppController c) async {
    if (_noticesShown || c.notices.isEmpty) return;
    _noticesShown = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bilgilendirme'),
        content: SingleChildScrollView(child: Text(c.notices.join('\n\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    c.notices.clear();
  }

  // ---------------------------------------------------------------- menüler

  Future<void> _push(Widget screen) async {
    final c = ref.read(appControllerProvider);
    c.pauseAll();
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));
  }

  void _menu() {
    final c = ref.read(appControllerProvider);
    c.pauseAll();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (c.newerIssueId != null)
                ListTile(
                  leading: const Icon(Icons.fiber_new),
                  title: const Text('Bugünün sayısına geç'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openIssue(c.newerIssueId!);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('Sayfa seçici'),
                onTap: () {
                  Navigator.pop(ctx);
                  _picker();
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Arşiv'),
                onTap: () {
                  Navigator.pop(ctx);
                  _push(ArchiveScreen(onOpenIssue: _openIssue));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('İstatistikler'),
                onTap: () {
                  Navigator.pop(ctx);
                  _push(const StatsScreen());
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Ayarlar'),
                onTap: () {
                  Navigator.pop(ctx);
                  _push(const SettingsScreen());
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Nasıl oynanır?'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showOnboarding(c);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openIssue(String id) async {
    final c = ref.read(appControllerProvider);
    await c.openIssue(id, createIfMissing: true);
    _pages.jump(0);
    c.setLastPage(0);
  }

  void _picker() {
    final c = ref.read(appControllerProvider);
    final issue = c.issue;
    if (issue == null) return;
    c.pauseAll();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final pal = ctx.pal;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Sayfalar', style: serifStyle(pal.ink, 22)),
              const SizedBox(height: 4),
              Text(
                '${issue.number}. Sayı · ${trDate(issue.date)}',
                style: sansStyle(pal.inkSoft, 14),
              ),
              const SizedBox(height: 10),
              for (final p in issue.pages)
                _PickerRow(
                  page: p,
                  current: p.index == _pages.index,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pages.goTo(p.index);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ çizim

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appControllerProvider);
    final issue = c.issue;
    final pal = context.pal;
    if (issue == null) {
      return const Scaffold(body: Center(child: Text('Sayı açılamadı.')));
    }
    final index = _pages.index.clamp(0, issue.pages.length - 1);
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        // Sistem geri hareketi: önce önceki sayfaya döner.
        if (!didPop && index > 0) _pages.prev();
      },
      child: Scaffold(
        backgroundColor: pal.paperDeep,
        body: SafeArea(
          child: Column(
            children: [
              _SaveBanner(controller: c),
              if (c.newerIssueId != null && c.newerIssueId != issue.id)
                _NewIssueBanner(
                  id: c.newerIssueId!,
                  onOpen: () => _openIssue(c.newerIssueId!),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: PageTurner(
                    key: ValueKey(issue.id),
                    controller: _pages,
                    itemCount: issue.pages.length,
                    reduceMotion: c.settings.reduceMotion,
                    onTurn: (forward) => c.sfxPage(back: !forward),
                    onChanged: (i) {
                      c.pauseAll();
                      c.setLastPage(i);
                    },
                    itemBuilder: (context, i) => NewspaperPageView(
                      key: ValueKey('${issue.id}/$i'),
                      issue: issue,
                      page: issue.pages[i],
                      pageCount: issue.pages.length,
                      onMenu: _menu,
                      onPicker: _picker,
                    ),
                  ),
                ),
              ),
              _Footer(
                issue: issue,
                index: index,
                onPrev: index > 0 ? _pages.prev : null,
                onNext: index < issue.pages.length - 1 ? _pages.next : null,
                onGo: _pages.goTo,
              ),
              // Ekranın altında banner (hazır olana dek yer kaplamaz).
              Center(child: c.ads.banner()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.issue,
    required this.index,
    required this.onPrev,
    required this.onNext,
    required this.onGo,
  });
  final NewspaperIssue issue;
  final int index;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final void Function(int) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final pal = context.pal;
    return Container(
      color: pal.paperDeep,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Önceki sayfa',
            icon: const Icon(Icons.chevron_left, size: 30),
            onPressed: onPrev,
          ),
          Expanded(
            child: Semantics(
              label: 'Sayfa ${index + 1} / ${issue.pages.length}',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (final p in issue.pages)
                        Expanded(
                          child: InkWell(
                            onTap: () => onGo(p.index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 8,
                              ),
                              child: _Segment(
                                current: p.index == index,
                                done: p.slots.every(
                                  (s) =>
                                      c.sessionFor(s)?.meta.completed ?? false,
                                ),
                                progress: _avg(c, p),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    'Sayfa ${index + 1} / ${issue.pages.length}',
                    style: sansStyle(pal.inkSoft, 12, w: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sonraki sayfa',
            icon: const Icon(Icons.chevron_right, size: 30),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }

  static double _avg(AppController c, NewspaperPage p) {
    var t = 0.0;
    for (final s in p.slots) {
      t += c.sessionFor(s)?.game.progress ?? 0;
    }
    return t / p.slots.length;
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.current,
    required this.done,
    required this.progress,
  });
  final bool current;
  final bool done;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: current ? 8 : 5,
          decoration: BoxDecoration(
            color: pal.rule.withValues(alpha: 0.6),
            border: current ? Border.all(color: pal.ink) : null,
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: done ? 1 : progress.clamp(0.0, 1.0),
            child: Container(
              color: done ? pal.ok : pal.ink.withValues(alpha: 0.7),
            ),
          ),
        ),
        if (done) Icon(Icons.check, size: 9, color: pal.paper),
      ],
    );
  }
}

class _PickerRow extends ConsumerWidget {
  const _PickerRow({
    required this.page,
    required this.current,
    required this.onTap,
  });
  final NewspaperPage page;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final pal = context.pal;
    final parts = <String>[];
    var done = 0;
    var progress = 0.0;
    for (final s in page.slots) {
      final ses = c.sessionFor(s);
      if (ses == null) continue;
      parts.add('${ses.def.type.shortLabel} (${ses.def.difficulty.label})');
      if (ses.meta.completed) done++;
      progress += ses.game.progress;
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: current ? pal.ink : pal.rule,
          width: current ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Text('${page.index + 1}', style: serifStyle(pal.ink, 28)),
        title: Text(
          parts.join('  +  '),
          style: sansStyle(pal.ink, 16, w: FontWeight.w700),
        ),
        subtitle: Text(
          done == page.slots.length
              ? 'Tamamlandı'
              : '$done / ${page.slots.length} tamamlandı · %${(progress / page.slots.length * 100).round()} dolu',
        ),
        trailing: current
            ? const Icon(Icons.bookmark)
            : done == page.slots.length
            ? Icon(Icons.check_circle_outline, color: pal.ok)
            : null,
      ),
    );
  }
}

class _SaveBanner extends StatelessWidget {
  const _SaveBanner({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return ValueListenableBuilder<String?>(
      valueListenable: controller.store.saveError,
      builder: (context, err, _) {
        if (err == null) return const SizedBox.shrink();
        return Material(
          color: pal.bad,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'İlerlemeniz şu an kaydedilemiyor. Uygulamayı kapatmadan önce yeniden deneyin.',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () async {
                    final ok = await controller.store.retry();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Kayıt tamamlandı.'
                                : 'Hâlâ kaydedilemiyor. Cihaz depolamasında yer olduğundan emin olun.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Yeniden dene'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NewIssueBanner extends StatelessWidget {
  const _NewIssueBanner({required this.id, required this.onOpen});
  final String id;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Material(
      color: pal.selection,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            Icon(Icons.newspaper, color: pal.ink, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Yeni sayı hazır (${trDate(NewspaperIssue.parseIssueDate(id))}). Çözdüğünüz sayı olduğu gibi duruyor.',
                style: sansStyle(pal.ink, 13),
              ),
            ),
            TextButton(onPressed: onOpen, child: const Text('Geç')),
          ],
        ),
      ),
    );
  }
}
