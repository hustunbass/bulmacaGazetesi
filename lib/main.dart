import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/ads.dart';
import 'core/sfx.dart';
import 'data/content_library.dart';
import 'data/file_store.dart';
import 'state/app_controller.dart';
import 'state/providers.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final library = await ContentLibrary.loadAssets(rootBundle);
    final docs = await getApplicationDocumentsDirectory();
    final store = FileStore(Directory('${docs.path}/bulmaca_gazetesi'));
    final sfx = AudioSfx();
    await sfx.init();
    final ads = AdMobAds();
    final controller = AppController(
      store: store,
      library: library,
      sfx: sfx,
      ads: ads,
    );
    await controller.init();
    runApp(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const BulmacaApp(),
      ),
    );
    // Onay formu ve SDK başlatma oyunu beklemez; ilk karede sonra başlar.
    unawaited(ads.init());
  } on Object catch (e) {
    // İçerik veya depolama hiç açılamadıysa sakin bir hata ekranı göster.
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                'Uygulama başlatılamadı. Verileriniz silinmedi.\n\nAyrıntı: $e',
                style: const TextStyle(fontSize: 17),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
