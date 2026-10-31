import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ödüllü reklamın sonucu.
enum RewardOutcome {
  /// Kullanıcı reklamı izleyip ödülü kazandı.
  earned,

  /// Reklam gösterildi ama ödül kazanılmadan kapatıldı.
  dismissed,

  /// Reklam yüklenemedi/gösterilemedi (çevrimdışı, doldurma yok, onay yok).
  unavailable,
}

/// Reklamlar. Arayüz yalnızca bu soyutlamayı bilir; testlerde [NoopAds].
abstract class Ads {
  /// Bu derlemede reklam gösterimi açık mı (ipucu reklam adımı buna bakar).
  bool get enabled;

  /// Başarısızsa sonraki çağrıda yeniden dener; başarılıysa bir şey yapmaz.
  Future<void> init();

  /// Ekranın altına konan banner. Hazır değilse boş yer kaplamayan widget.
  Widget banner();

  /// Ödüllü reklamı gösterir ve sonucu bildirir.
  Future<RewardOutcome> showRewarded();

  /// Reklam gizlilik seçenekleri (AB/İngiltere onay formu) gerekli mi.
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();
}

class NoopAds implements Ads {
  const NoopAds();
  @override
  bool get enabled => false;
  @override
  Future<void> init() async {}
  @override
  Widget banner() => const SizedBox.shrink();
  @override
  Future<RewardOutcome> showRewarded() async => RewardOutcome.unavailable;
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
}

/// Reklam birimi kimlikleri.
///
/// * iOS: AdMob hesabındaki gerçek kimlikler.
/// * Android: henüz gerçek kimlik verilmedi → Google'ın resmî TEST kimlikleri.
/// * Hata ayıklama (debug/profile) derlemelerinde ve `--dart-define=ADS_TEST=true`
///   ile alınan derlemelerde her zaman Google test reklamları kullanılır. Kendi
///   gerçek reklamınıza tıklamak AdMob hesabının askıya alınmasına yol açabilir.
class AdIds {
  AdIds._();

  static const forceTest = bool.fromEnvironment('ADS_TEST');
  static bool get useTest => forceTest || !kReleaseMode;

  // Google'ın herkese açık test kimlikleri.
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';

  // Gerçek iOS kimlikleri (AdMob konsolundan).
  static const iosAppId = 'ca-app-pub-9207046302495275~1413836129';
  static const _realRewardedIos = 'ca-app-pub-9207046302495275/2770103640';
  static const _realBannerIos = 'ca-app-pub-9207046302495275/8377653544';

  static String get rewarded {
    if (Platform.isIOS) return useTest ? _testRewardedIos : _realRewardedIos;
    return _testRewardedAndroid; // Gerçek Android birimi verilince değiştirin.
  }

  static String get banner {
    if (Platform.isIOS) return useTest ? _testBannerIos : _realBannerIos;
    return _testBannerAndroid; // Gerçek Android birimi verilince değiştirin.
  }

  /// Gerçek reklam birimlerinde test cihazı olarak işaretlenecek cihaz kimlikleri
  /// (Xcode günlüğünde "To get test ads on this device, set testDeviceIdentifiers
  /// to ..." satırında görünür). Buraya eklenen cihazlar gerçek birimde de test
  /// reklamı görür.
  static const testDeviceIds = <String>[];
}

/// Google AdMob uygulaması.
///
/// Açılış sırası: UMP onay bilgisi güncellenir → gerekirse onay formu gösterilir
/// → onay verildiyse SDK başlatılır → ödüllü reklam önceden yüklenir. Hiçbir
/// adım oyunu bekletmez; hata olursa reklam sessizce kapalı kalır.
class AdMobAds implements Ads {
  bool _ready = false;
  RewardedAd? _rewarded;
  Completer<void>? _loading;
  final ValueNotifier<bool> _readyNotifier = ValueNotifier(false);

  @override
  bool get enabled => true;

  bool _initializing = false;

  /// Başarıyla başlatıldıysa hiçbir şey yapmaz; başarısızsa (ör. ağ yok) yeniden
  /// dener. Uygulama öne her döndüğünde de çağrılır.
  @override
  Future<void> init() async {
    if (_ready || _initializing) return;
    _initializing = true;
    try {
      await _initOnce();
    } finally {
      _initializing = false;
    }
  }

  Future<void> _initOnce() async {
    try {
      // Onay bilgisi ağ gerektirir: ilk denemeler başarısız olursa kısa aralıkla
      // yeniden denenir.
      var canRequest = false;
      for (var attempt = 0; attempt < 3 && !canRequest; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(seconds: 4 * attempt));
        }
        await _gatherConsent();
        canRequest = await ConsentInformation.instance.canRequestAds();
      }
      if (!canRequest) {
        debugPrint('Reklam: onay yok / alınamadı, reklamlar şimdilik kapalı.');
        return;
      }
      if (AdIds.testDeviceIds.isNotEmpty) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: AdIds.testDeviceIds),
        );
      }
      await MobileAds.instance.initialize();
      _ready = true;
      _readyNotifier.value = true;
      unawaited(_loadRewarded());
    } on Object catch (e) {
      debugPrint('Reklam başlatılamadı, reklamlar kapalı: $e');
    }
  }

  Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((error) {
            if (error != null) debugPrint('Onay formu: ${error.message}');
          });
        } on Object catch (e) {
          debugPrint('Onay formu hatası: $e');
        }
        if (!done.isCompleted) done.complete();
      },
      (error) {
        debugPrint('Onay bilgisi alınamadı: ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
  }

  Future<void> _loadRewarded() {
    if (_rewarded != null) return Future.value();
    final running = _loading;
    if (running != null) return running.future;
    final c = _loading = Completer<void>();
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loading = null;
          if (!c.isCompleted) c.complete();
        },
        onAdFailedToLoad: (e) {
          debugPrint('Ödüllü reklam yüklenemedi: ${e.message}');
          _loading = null;
          if (!c.isCompleted) c.complete();
        },
      ),
    );
    return c.future;
  }

  @override
  Future<RewardOutcome> showRewarded() async {
    if (!_ready) return RewardOutcome.unavailable;
    if (_rewarded == null) {
      await _loadRewarded().timeout(
        const Duration(seconds: 6),
        onTimeout: () {},
      );
    }
    final ad = _rewarded;
    if (ad == null) {
      unawaited(_loadRewarded());
      return RewardOutcome.unavailable;
    }
    _rewarded = null;
    final result = Completer<RewardOutcome>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        unawaited(_loadRewarded());
        if (!result.isCompleted) {
          result.complete(
            earned ? RewardOutcome.earned : RewardOutcome.dismissed,
          );
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Ödüllü reklam gösterilemedi: ${error.message}');
        ad.dispose();
        unawaited(_loadRewarded());
        if (!result.isCompleted) result.complete(RewardOutcome.unavailable);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } on Object catch (e) {
      debugPrint('Ödüllü reklam hatası: $e');
      if (!result.isCompleted) result.complete(RewardOutcome.unavailable);
    }
    return result.future;
  }

  @override
  Widget banner() => ValueListenableBuilder<bool>(
    valueListenable: _readyNotifier,
    builder: (context, ready, _) =>
        ready ? const _AdBannerView() : const SizedBox.shrink(),
  );

  @override
  Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) debugPrint('Gizlilik seçenekleri: ${error.message}');
      done.complete();
    });
    await done.future;
  }
}

/// Kompakt banner: telefonda 320x50, geniş ekranda (tablet) 728x90. Yüklenene
/// dek yer kaplamaz; puzzle alanını yemesin diye sabit ve alçak boyut seçilir.
class _AdBannerView extends StatefulWidget {
  const _AdBannerView();

  @override
  State<_AdBannerView> createState() => _AdBannerViewState();
}

class _AdBannerViewState extends State<_AdBannerView> {
  BannerAd? _ad;
  AdSize? _size;
  AdSize? _requested;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wide = MediaQuery.sizeOf(context).width >= 740;
    final want = wide ? AdSize.leaderboard : AdSize.banner;
    if (_requested != want) {
      _requested = want;
      _load(want);
    }
  }

  void _load(AdSize size) {
    _ad?.dispose();
    _ad = null;
    _size = null;
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (a) {
          if (!mounted) {
            a.dispose();
            return;
          }
          setState(() {
            _ad = a as BannerAd;
            _size = size;
          });
        },
        onAdFailedToLoad: (a, e) {
          debugPrint('Banner yüklenemedi: ${e.message}');
          a.dispose();
        },
      ),
    );
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad, size = _size;
    if (ad == null || size == null) return const SizedBox.shrink();
    return SizedBox(
      width: size.width.toDouble(),
      height: size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
