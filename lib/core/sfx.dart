import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Ses efektleri. Arayüz yalnızca bu soyutlamayı bilir; testlerde [NoopSfx].
abstract class Sfx {
  void pen();
  void erase();
  void page({bool back = false});
  Future<void> dispose();
}

class NoopSfx implements Sfx {
  const NoopSfx();
  @override
  void pen() {}
  @override
  void erase() {}
  @override
  void page({bool back = false}) {}
  @override
  Future<void> dispose() async {}
}

/// Gerçek ses. Özgün sentezlenmiş kısa dosyalar (assets/sounds, bkz.
/// tool/make_sounds.py) küçük bir oynatıcı havuzundan çalınır; hızlı yazarken
/// seslerin birbirini kesmemesi için havuz döner. İlk hatada ses kapanır ve
/// bir kez günlüğe yazılır; oyun etkilenmez.
class AudioSfx implements Sfx {
  static const _penFiles = [
    'sounds/pen1.wav',
    'sounds/pen2.wav',
    'sounds/pen3.wav',
  ];

  final List<AudioPlayer> _pen = [];
  AudioPlayer? _erase;
  AudioPlayer? _forward;
  AudioPlayer? _back;
  int _next = 0;
  bool _ok = false;

  Future<void> init() async {
    try {
      // Gazete okurken diğer sesleri kesmesin; sessiz modu desteklesin.
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          // iOS "ambient": sessiz modu destekler, diğer sesleri kesmez.
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {},
          ),
          android: AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
      // Oynatıcılar paralel hazırlanır; açılış sırayla beklemez.
      final all = await Future.wait([
        for (var i = 0; i < 4; i++)
          _load(_penFiles[i % _penFiles.length], 0.55),
        _load('sounds/erase.wav', 0.5),
        _load('sounds/page_forward.wav', 0.8),
        _load('sounds/page_back.wav', 0.8),
      ]);
      _pen.addAll(all.take(4));
      _erase = all[4];
      _forward = all[5];
      _back = all[6];
      _ok = true;
    } on Object catch (e) {
      debugPrint('Ses başlatılamadı, ses kapalı: $e');
    }
  }

  Future<AudioPlayer> _load(String file, double volume) async {
    final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setSource(AssetSource(file));
    await p.setVolume(volume);
    return p;
  }

  Future<void> _fire(AudioPlayer? p) async {
    if (!_ok || p == null) return;
    try {
      await p.seek(Duration.zero);
      await p.resume();
    } on Object catch (e) {
      _ok = false;
      debugPrint('Ses çalınamadı, ses kapatıldı: $e');
    }
  }

  @override
  void pen() {
    if (_pen.isEmpty) return;
    _next = (_next + 1) % _pen.length;
    _fire(_pen[_next]);
  }

  @override
  void erase() => _fire(_erase);

  @override
  void page({bool back = false}) => _fire(back ? _back : _forward);

  @override
  Future<void> dispose() async {
    for (final p in [..._pen, ?_erase, ?_forward, ?_back]) {
      await p.dispose();
    }
  }
}
