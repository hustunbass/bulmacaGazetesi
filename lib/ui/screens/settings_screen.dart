import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/paper.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final s = c.settings;
    final pal = context.pal;
    void set(AppSettings n) => c.updateSettings(n);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: PaperTextureOverlay(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ValueListenableBuilder<String?>(
                valueListenable: c.store.saveError,
                builder: (context, err, _) {
                  if (err == null) return const SizedBox.shrink();
                  return _Banner(
                    icon: Icons.error_outline,
                    text: err,
                    action: TextButton(
                      onPressed: () async {
                        final ok = await c.store.retry();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok ? 'Kaydedildi.' : 'Hâlâ kaydedilemedi.',
                            ),
                          ),
                        );
                      },
                      child: const Text('Yeniden dene'),
                    ),
                  );
                },
              ),
              for (final n in c.notices)
                _Banner(icon: Icons.info_outline, text: n),
              const _Header('Kâğıt'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final t in PaperTheme.values)
                      _ThemeChoice(
                        theme: t,
                        selected: s.paper == t,
                        onTap: () => set(s.copyWith(paper: t)),
                      ),
                  ],
                ),
              ),
              const _Header('Yazı büyüklüğü'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: 'Yazı büyüklüğü',
                      value: '%${(s.textScale * 100).round()}',
                      child: Slider(
                        min: 0.9,
                        max: 1.4,
                        divisions: 5,
                        value: s.textScale.clamp(0.9, 1.4),
                        label: '%${(s.textScale * 100).round()}',
                        activeColor: pal.ink,
                        onChanged: (v) =>
                            set(s.copyWith(textScale: (v * 100).round() / 100)),
                      ),
                    ),
                    Text(
                      'Örnek: Bulmaca postası, her sabah.',
                      style: serifStyle(pal.ink, 18, w: FontWeight.w400),
                    ),
                  ],
                ),
              ),
              const _Header('Oyun'),
              _Toggle(
                'Ses (kalem ve gazete sayfası sesleri)',
                s.sound,
                (v) => set(s.copyWith(sound: v)),
              ),
              _Toggle(
                'Titreşim',
                s.haptics,
                (v) => set(s.copyWith(haptics: v)),
              ),
              _Toggle(
                'Azaltılmış hareket',
                s.reduceMotion,
                (v) => set(s.copyWith(reduceMotion: v)),
                sub: 'Sayfa çevirme ve geçişlerde animasyonları azaltır.',
              ),
              _Toggle(
                'Anında doğru/yanlış göster',
                s.liveFeedback,
                (v) => set(s.copyWith(liveFeedback: v)),
                sub:
                    'Yanlış harf yazınca kırmızı ve altı çizili olur; bir kelimeyi '
                    'doğru tamamlayınca kelime yeşile döner. “Kontrol” düğmesi yine çalışır.',
              ),
              _Toggle(
                'Hataları vurgula',
                s.highlightErrors,
                (v) => set(s.copyWith(highlightErrors: v)),
                sub: 'Yanlış harfler renk ve işaretle gösterilir.',
              ),
              _Toggle(
                'Süreyi göster',
                s.showTimer,
                (v) => set(s.copyWith(showTimer: v)),
              ),
              const _Header('Sudoku'),
              _Toggle(
                'Adayları otomatik temizle',
                s.sudokuAutoClear,
                (v) => set(s.copyWith(sudokuAutoClear: v)),
                sub:
                    'Bir rakam yazılınca satır, sütun ve kutudaki aday notları silinir.',
              ),
              _Toggle(
                'Çakışmaları göster',
                s.sudokuShowConflicts,
                (v) => set(s.copyWith(sudokuShowConflicts: v)),
                sub:
                    'Aynı satır, sütun veya kutuda tekrar eden rakamları işaretler.',
              ),
              const _Header('Tanıtım'),
              ListTile(
                minTileHeight: 56,
                title: Text(
                  'Tanıtımı tekrar göster',
                  style: sansStyle(pal.ink, 17),
                ),
                trailing: const Icon(Icons.replay),
                onTap: () {
                  set(s.copyWith(onboardingDone: false));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Tanıtım bir sonraki açılışta yeniden gösterilecek.',
                      ),
                    ),
                  );
                },
              ),
              const _Header('Gizlilik ve lisanslar'),
              const _Para(
                'Gizlilik: Hesap yoktur. İlerlemeniz, ayarlarınız ve '
                'istatistikleriniz yalnızca cihazınızda saklanır; bunları biz '
                'toplamayız. Oyun internet olmadan da oynanır.',
              ),
              const _Para(
                'Reklamlar: Uygulama ücretsizdir ve Google AdMob reklamları '
                'gösterir. Reklam için Google cihaz tanımlayıcıları ve reklam '
                'etkileşim verilerini işleyebilir. Bulunduğunuz bölgeye göre '
                'size onay seçenekleri sunulur. Reklamlar internet gerektirir.',
              ),
              FutureBuilder<bool>(
                future: c.ads.privacyOptionsRequired(),
                builder: (context, snap) => snap.data == true
                    ? ListTile(
                        minTileHeight: 56,
                        title: Text(
                          'Reklam gizlilik seçenekleri',
                          style: sansStyle(pal.ink, 17),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: c.ads.showPrivacyOptions,
                      )
                    : const SizedBox.shrink(),
              ),
              const _Para(
                'Yazı tipleri: Playfair Display ve Source Sans 3, SIL Open Font '
                'License 1.1 ile lisanslıdır; telif hakları ilgili yazı tipi '
                'tasarımcılarına aittir (Playfair Display: Claus Eggers Sørensen; '
                'Source Sans 3: Adobe). Lisansların tam metinleri proje '
                'deposundaki licenses klasöründedir.',
              ),
              const _Para(
                'İçerik: Kitaptaki bulmacalar proje içi özgün içeriktir. Kaynak '
                've lisans bilgisi her bulmacanın kendi kaydında saklanır.',
              ),
              ListTile(
                minTileHeight: 56,
                title: Text(
                  'Açık kaynak lisansları',
                  style: sansStyle(pal.ink, 17),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Bulmaca Gazetesi',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(text, style: serifStyle(pal.ink, 20)),
          ),
          const SizedBox(height: 4),
          const NewsRule(),
        ],
      ),
    );
  }
}

class _Para extends StatelessWidget {
  const _Para(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Text(
      text,
      style: sansStyle(context.pal.ink, 16, h: 1.4, w: FontWeight.w400),
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.title, this.value, this.onChanged, {this.sub});
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SwitchListTile(
      title: Text(title, style: sansStyle(pal.ink, 17)),
      subtitle: sub == null
          ? null
          : Text(sub!, style: sansStyle(pal.inkSoft, 14, w: FontWeight.w400)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: pal.ink, width: 1),
        color: pal.paperDeep,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: pal.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: sansStyle(pal.ink, 15, h: 1.35, w: FontWeight.w400),
                ),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.theme,
    required this.selected,
    required this.onTap,
  });
  final PaperTheme theme;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(theme);
    final pal = context.pal;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Kâğıt: ${theme.label}${selected ? ', seçili' : ''}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 96, minHeight: 80),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? pal.ink : pal.rule,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.paper,
                    border: Border.all(color: p.rule),
                  ),
                  child: Text('Abc', style: serifStyle(p.ink, 16)),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) ...[
                      Icon(Icons.check, size: 16, color: pal.ink),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        theme.label,
                        style: sansStyle(pal.ink, 14, w: FontWeight.w600),
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
  }
}
