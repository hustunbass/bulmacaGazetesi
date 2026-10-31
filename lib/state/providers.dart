import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_controller.dart';

/// Uygulamanın tek durum sahibi. `main` içinde oluşturulan denetleyici ile
/// geçersiz kılınır (override); testlerde sahte depoyla değiştirilebilir.
final appControllerProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw UnimplementedError('appControllerProvider override edilmeli'),
);
