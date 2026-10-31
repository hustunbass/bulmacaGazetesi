import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/paper.dart';

class _Card {
  const _Card(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final List<String> body;
}

const _cards = <_Card>[
  _Card(Icons.menu_book_outlined, 'Sayfaları çevirin', [
    'Her gün yeni bir gazete sayısı var. Sayfayı kenardan sürükleyerek '
        'ya da alttaki düğmelerle çevirebilirsiniz.',
    'Her sayfada iki bulmaca bulunur.',
  ]),
  _Card(Icons.zoom_in_outlined, 'Bulmacayı büyütün', [
    'Bir bulmacaya dokunun; ekranı kaplayacak şekilde açılır ve '
        'rahatça çözebilirsiniz.',
  ]),
  _Card(Icons.refresh, 'Sıfırla ve yeni bulmaca', [
    'Sıfırla: aynı bulmacayı baştan başlatır.',
    'Yeni bulmaca: yalnızca bu yuvaya farklı bir bulmaca getirir; sayfadaki '
        'diğer bulmaca değişmez.',
    'Mevcut ilerlemeniz silinmez, arşivlenir. İpucu istemek tamamen size kalmış.',
  ]),
  _Card(Icons.grid_on_outlined, 'Kare, Klasik ve Çengel', [
    'Kare: ortalama boyda, numaralı geleneksel bir bulmaca.',
    'Klasik: aynı kurallarla, ama daha büyük, daha yoğun, uzun cevaplı ve '
        'kategorili bir gazete bulmacası. İki ayrı kural seti değildir.',
    'Çengel: ipuçları ızgaranın içinde, oklarla gösterilir.',
  ]),
];

/// İlk kullanım tanıtımı. Ayarı çağıran taraf işler.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _finished = false;

  bool get _last => _page == _cards.length - 1;

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  void _next() {
    if (_last) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Scaffold(
      body: PaperTextureOverlay(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton(
                    onPressed: _finish,
                    child: const Text('Atla'),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _cards.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final card = _cards[i];
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
                      children: [
                        Icon(card.icon, size: 48, color: pal.ink),
                        const SizedBox(height: 16),
                        Semantics(
                          header: true,
                          child: Text(
                            card.title,
                            style: serifStyle(pal.ink, 28, h: 1.15),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const NewsRule(),
                        const SizedBox(height: 16),
                        for (final p in card.body)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              p,
                              style: sansStyle(
                                pal.ink,
                                18,
                                h: 1.4,
                                w: FontWeight.w400,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Sayfa ${_page + 1} / ${_cards.length}',
                        child: ExcludeSemantics(
                          child: Row(
                            children: [
                              for (var i = 0; i < _cards.length; i++)
                                Container(
                                  width: i == _page ? 18 : 8,
                                  height: 4,
                                  margin: const EdgeInsets.only(right: 6),
                                  color: i == _page ? pal.ink : pal.rule,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: _next,
                      child: Text(_last ? 'Başla' : 'İleri'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
