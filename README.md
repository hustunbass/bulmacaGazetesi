# Bulmaca Gazetesi

Türkçe, çevrimdışı çalışan dijital gazete bulmaca eki (Flutter, Android + iOS).
Her gazete sayfasında iki bulmaca bulunur; çengel, kare, klasik ve Sudoku çözülebilir.

> Durum: çalışan bir ilk sürümdür. Doğrulananlar ve **doğrulanmayanlar** en altta
> "Doğrulama durumu ve bilinen eksikler" bölümünde dürüstçe yazılıdır.

## Kurulum ve çalıştırma

```bash
flutter pub get
flutter run                 # bağlı cihaz/emülatör
flutter analyze
flutter test                # 101 test
flutter build apk --debug   # Android
```

Geliştirici araçları (uygulama içinde çalışmaz) Flutter'ın kendi Dart'ı ile çalıştırılır:

```bash
dart tool/make_puzzles.dart   # içerik üretimi + doğrulama (≈1 dk)
```

Gereksinim: Flutter 3.41 (Dart 3.11). Hesap, sunucu veya internet gerekmez.

## Ürün tanımları

- **Çengel**: ipuçları ızgara içindeki soru hücrelerinde, oklar yönü gösterir.
- **Kare**: geleneksel numaralı ızgara, siyah bloklar, "Soldan sağa / Yukarıdan aşağıya" listeleri.
- **Klasik**: kareyle **aynı kural motorunu** paylaşır; farkı boyutta (15×15), yoğunlukta
  (daha çok ve daha uzun cevap), kategorili sorularda ve odak modunda yakınlaştırmadadır.
  İki ayrı kural seti değildir.
- **Sudoku**: 9×9, not modu, çakışma gösterimi, otomatik aday temizleme, geri al/yinele.

## Mimari

| Katman | Yer | Not |
|---|---|---|
| Alan/oyun motorları | `lib/domain/` | Widget'tan bağımsız, birim testli: `WordGame`, `SudokuGame`, `SudokuSolver`, `ContentValidator`, `IssuePlanner` |
| Veri | `lib/data/` | `ContentLibrary` (JSON → doğrulanmış havuz), `FileStore` (kayıt), `AppSettings` |
| Durum | `lib/state/` | `AppController` (Riverpod ile sağlanır), `AttemptSession` (deneme başına tek canlı durum) |
| Arayüz | `lib/ui/` | Gazete sayfası, sayfa çevirme, odak modu, ızgaralar, ekranlar |

Sayfa görünümü ve odak modu **aynı** `AttemptSession` nesnesini kullanır; durum kopyası yoktur.

### Kayıt (Drift yerine dosya deposu)
Drift/SQLite yerine dosya tabanlı JSON deposu seçildi: veri küçük ve belge biçimlidir,
kod üretimi/native bağımlılık gerekmez, testler geçici dizinle çalışır. Özellikler:
atomik yazma (geçici dosya + rename), yol başına birleştirilmiş sıralı yazma kuyruğu,
`storage.json` içinde şema sürümü ve migration kancası, bozuk dosyanın silinmeden
`quarantine/` altına alınması, yazma hatasında görünür uyarı ve "Yeniden dene".
Sınır: sorgular bellekte yapılır; çok büyük arşivlerde SQLite'a geçmek gerekebilir.

Klasör: `<uygulama belgeleri>/bulmaca_gazetesi/` → `issues/`, `attempts/`, `snapshots/`
(bir denemenin bağlı olduğu bulmaca sürümü), `generated/` (cihazda üretilen Sudoku),
`completions.json`, `settings.json`.

## İçerik biçimi ve yeni bulmaca ekleme

İçerik `assets/puzzles/*.json` dosyalarındadır (her dosya bir bulmaca dizisi). Widget koduna
dokunmadan eklenir; uygulama açılışında her kayıt `ContentValidator`'dan geçer, geçmeyenler
havuza alınmaz ve nedenleri `ContentLibrary.rejected` içinde tutulur.

Ortak alanlar: `schema`, `id` (küçük harf/rakam/-/_, benzersiz), `version` (≥1), `type`
(`cengel|kare|klasik|sudoku`), `difficulty` (`kolay|orta|zor`), `title`, `source`, `license`.

Kelime bulmacaları: `rows`, `cols`, `grid` (her satır: harf = cevap hücresi, `#` = oynanamaz),
`entries`:
- kare/klasik: `{id, n, dir:"A|D", r, c, answer, clue, cat}` — `n` standart numaralandırmayla uyuşmalı;
  klasikte `cat` zorunlu.
- çengel: `{id, dir, clueR, clueC, answer, clue}` — soru hücresi cevabın hemen öncesindedir;
  hücre başına yön başına en çok bir ipucu; ipucu ≤ 70 karakter.

Cevap sözleşmesi: yalnızca büyük Türkçe harf (boşluk, tire, kesme **yok**; "KARA DENİZ" → "KARADENİZ").
`Ş≠S`, `İ≠I`. İpucundaki harf sayısı gerçek hücre sayısıdır.

Sudoku: `givens` ve `solution` (81 karakter). Tek çözüm ve bildirilen zorluğun mantıksal
derecelendirmeyle uyuşması doğrulanır.

Doğrulayıcının yakaladıkları: kesişimde harf uyuşmazlığı, ızgaraya sığmama, tanımsız/ulaşılamayan
dizi, boşta hücre, bağlantısızlık, yinelenen kimlik/cevap, numara hatası, aşırı uzun ipucu,
çok çözümlü Sudoku.

Yeni bulmaca eklemek için: (1) JSON'u `assets/puzzles/` altına koyun, (2) `flutter test test/content_test.dart`
çalıştırın, (3) ya da `tool/word_bank.dart` bankasına özgün ipuçları ekleyip `tool/make_puzzles.dart` ile üretin.
**Bu "sınırsız bulmaca" değildir:** kelime bulmacası kalitesi bir editöryal sürece bağlıdır; araç yalnızca
bankadaki özgün ipuçlarını kullanır. Sudoku ise cihazda doğrulanarak üretilebilir ("Yeni bulmaca" havuz bitince).

## Lisanslar
- Yazı tipleri: Playfair Display, Source Sans 3 — SIL Open Font License 1.1 (`licenses/`).
- İçerik: bu projeye özgü yazılmıştır; telifli gazete bulmacası kopyalanmamıştır. Her bulmacada
  `source` ve `license` alanı saklanır.
- Paketler: Flutter, flutter_riverpod, path_provider, intl (BSD/MIT); uygulama içi Lisanslar sayfasından görülür.

## Doğrulama durumu ve bilinen eksikler

Çalıştırılıp geçenler: `flutter analyze` (0 sorun), `dart format`, `flutter test` (101 test),
`flutter build apk --debug` (başarılı).

Çalıştırılamayan / ölçülmeyen:
- **iOS**: iPhone 16 Pro (iOS 18.6) simülatöründe derlenip açıldı; temel akış (odak modu, Türkçe klavye,
  kayıtlı ilerleme) görsel olarak doğrulandı. `objective_c` native derleme adımı bu makinede başarısız
  olduğu için `pubspec.yaml`'da `path_provider_foundation: 2.4.1` geçici override'ı vardır. Gerçek iOS cihazı
  ve tüm akışlar (sayfa çevirme dahil) elle taranmadı.
- **Gerçek cihazda/emülatörde çalıştırma ve profile performans ölçümü yapılmadı.** Performans hakkında
  ölçülmüş bir iddia yoktur. Ekran görüntüleri yalnızca widget-test ortamından alındı.
- Sayfa çevirme: perspektifli döndürme + gölge (gerçek kâğıt bükülmesi değil). Düşük kare hızında kaymaya,
  "animasyonları azalt"ta çapraz geçişe düşer. Gerçek cihazda görsel kalitesi gözle doğrulanmadı.
- Ses ayarı kaydedilir ama ses efekti yoktur. Titreşim klavye/tamamlamada çalışır.
- Arayüz metinleri kodda Türkçe sabit metindir; ARB tabanlı yerelleştirme **yok** (yalnızca Flutter'ın
  `tr` yerelleştirme temsilcileri bağlı).
- Çengelde ızgara sparse'tır (kelimeler kesişimle kurulur, yoğun bir basılı çengel kadar dolu değildir);
  ipuçları editöryal olarak tek tek gözden geçirilmedi, belirsiz ipucu kalmış olabilir.
- İçerik: her türde 100 bulmaca (çengel, kare, klasik, Sudoku; toplam 400). Kelime bulmacalarındaki cevap/ipuçları yapay
  zekâ yardımıyla yazılmış özgün bankadan (≈1500 giriş) üretildi; ipuçları insan editör tarafından tek tek gözden
  geçirilmedi, yalnızca otomatik doğrulama ve örnekleme okuması yapıldı. Belirsiz/yanlış ipucu görürseniz bankadan çıkarılmalıdır.
  Günlük sayı havuzdan seçildiği için içerik 100 günden sonra tekrar eder.
- Sudoku "zor" sınıfı geniş bir aralıktır (tek aday/tek yer ile çözülemeyen her şey).
- Erişilebilirlik: semantics etiketleri test edildi; TalkBack/VoiceOver ile gerçek cihaz denemesi yapılmadı.

## Sonradan eklenenler
- **Sayfa çevirme:** gerçek köşe kıvrılması (geometri `lib/ui/widgets/page_curl.dart`, birim testli).
- **Sesler:** özgün sentezlenmiş kalem/silgi/sayfa sesleri (`tool/make_sounds.py`, `assets/sounds`). Ayardan kapatılabilir.
  Sesin kulakla değerlendirmesi yapılmadı; yalnızca iOS'ta hatasız başlatıldığı ve testte doğru anlarda tetiklendiği doğrulandı.
- **Anında doğru/yanlış:** yanlış harf kırmızı + kalın alt çizgi; tamamen doğru kelime yeşil zemin + ✓. Elle "Kontrol" yine çalışır.
  Ayarlardan kapatılabilir (varsayılan açık).
- **Ad ve ikon:** ana ekran adı "Bulmaca Gazetesi"; özgün ikon `tool/make_icon.py` ile üretilir (iOS + Android adaptive).
- **App Store ekran görüntüleri:** `app_store_ekran_goruntuleri/` (iPhone 6.9" 1320×2868, iPad 13" 2064×2752, PNG/RGB).
  Yeniden üretmek için `tool/take_screenshots.sh`. iPad dikeyde gazete sayfası iki bulmacayla ekranın üst yarısını doldurur
  (alt yarı boş kalır); iPad yatay görüntü alınamadı (iPad çoklu görev yön kilidine izin vermiyor).
- iOS simülatör derlemesi için geçici `path_provider_foundation: 2.4.1` override'ı (pubspec.yaml) vardır.
- Bundle identifier: `com.hustunbas.bulmacaGazetesi` (iOS ve Android applicationId). Gizlilik bildirimi: `ios/Runner/PrivacyInfo.xcprivacy`.

## Reklamlar (Google AdMob)
- Paket: `google_mobile_ads 9.2.0`. Kod: `lib/core/ads.dart`. Testlerde `NoopAds`/`FakeAds` kullanılır; gerçek SDK yalnızca `main.dart`'ta.
- **Ödüllü reklam:** harf/kelime/Sudoku ipucu istenince önce “reklam izle” onayı sorulur, reklam izlenince ipucu verilir; yarıda
  kapatılırsa verilmez; reklam yüklenemezse (çevrimdışı vb.) oyun çevrimdışı oynanabilsin diye ipucu hediye edilir ve söylenir.
  Sudoku ipucu açıklaması reklamdan *sonra* gösterilir.
- **Banner:** ana ekranın altında; odak ekranında yalnızca yüksekliği ≥700 dp olan ekranlarda.
- **Onay (UMP):** açılışta onay bilgisi alınır, gerekiyorsa form gösterilir; başarısızsa 3 kez, sonra uygulama öne her
  dönüşünde yeniden denenir. Onay yoksa reklam gösterilmez. ATT (izleme izni) istenmez → kişiselleştirilmemiş reklam.
- **Kimlikler:** iOS uygulama `ca-app-pub-9207046302495275~1413836129`, ödüllü `…/2770103640`, banner `…/8377653544`.
  **Android için gerçek kimlik verilmedi**; AndroidManifest ve `AdIds` Google TEST kimliklerini kullanır.
- **Test reklamları:** hata ayıklama/profil derlemeleri ve `--dart-define=ADS_TEST=true` her zaman Google test birimlerini kullanır.
  TestFlight için: `flutter build ipa --dart-define=ADS_TEST=true`. App Store sürümü için bu bayrak OLMADAN derleyin.
  Kendi gerçek reklamınıza tıklamak AdMob hesabını askıya aldırabilir.
- **Doğrulanamayan:** bu makinedeki yerel proxy simülatörün TLS trafiğini bozduğu için canlı reklam (banner/ödüllü) görüntülenemedi;
  yalnızca derleme, SDK bağlama ve iş akışı mantığı (sahte reklamla) test edildi. Gerçek cihazda doğrulayın.
# bulmacaGazetesi
