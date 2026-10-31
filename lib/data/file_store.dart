import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Okunamayan/bozuk kayıt. Dosya karantinaya alınabilir; sessizce silinmez.
class StoreCorruptException implements Exception {
  StoreCorruptException(this.path, this.reason);
  final String path;
  final String reason;
  @override
  String toString() => 'StoreCorruptException($path): $reason';
}

/// Depo, uygulamadan daha yeni bir şemayla yazılmış.
class StoreTooNewException implements Exception {
  StoreTooNewException(this.found, this.supported);
  final int found;
  final int supported;
  @override
  String toString() => 'Kayıt şeması $found, desteklenen $supported';
}

typedef Migration = Future<void> Function(Directory root);

/// Dosya tabanlı, çevrimdışı JSON deposu.
///
/// Tasarım:
///  * Her kayıt ayrı dosyadır; tek bozuk dosya diğerlerini etkilemez.
///  * Yazma atomiktir (geçici dosya + rename).
///  * Yazmalar sıralı ve yol başına birleştirilir: aynı dosya için en son
///    durum yazılır, eski durum yenisini ezemez.
///  * Yazma başarısız olursa [saveError] dolar, bekleyen veri tutulur ve
///    [retry] ile yeniden denenir. Başarılıymış gibi davranılmaz.
///  * Şema sürümü `storage.json` içindedir; [migrations] ile yükseltilir.
///
/// Drift/SQLite yerine bu tasarım seçildi: veri küçük ve belge biçimlidir
/// (deneme başına bir kayıt), kod üretimi/native bağımlılık gerekmez ve
/// birim testleri geçici dizinle çalışır. Sorgular bellekte yapılır.
class FileStore {
  FileStore(this.root, {Map<int, Migration>? migrations})
    : migrations = migrations ?? const {};

  static const currentSchema = 1;

  final Directory root;
  final Map<int, Migration> migrations;

  /// Son yazma hatası (null = sorun yok).
  final ValueNotifier<String?> saveError = ValueNotifier(null);

  final Map<String, String> _pending = {};

  /// Şu an diske yazılmakta olan içerik (rename bitene dek okuyucular bunu görür).
  final Map<String, String> _inflight = {};
  Future<void>? _drain;

  File _file(String rel) => File('${root.path}/$rel');

  Future<void> init() async {
    await root.create(recursive: true);
    for (final d in const [
      'issues',
      'attempts',
      'quarantine',
      'snapshots',
      'generated',
    ]) {
      await Directory('${root.path}/$d').create(recursive: true);
    }
    final f = _file('storage.json');
    var found = currentSchema;
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString());
        found = (j as Map)['schema'] as int;
      } on Object {
        throw StoreCorruptException('storage.json', 'Şema bilgisi okunamadı');
      }
    }
    if (found > currentSchema) throw StoreTooNewException(found, currentSchema);
    for (var v = found; v < currentSchema; v++) {
      final m = migrations[v];
      if (m == null) {
        throw StoreCorruptException('storage.json', 'v$v için geçiş yok');
      }
      await m(root);
    }
    if (found != currentSchema || !await f.exists()) {
      await _atomicWrite(f, jsonEncode({'schema': currentSchema}));
    }
  }

  /// Dosya yoksa null. Bozuksa [StoreCorruptException].
  Future<Map<String, dynamic>?> readJson(String rel) async {
    // Bekleyen yazma varsa en yeni durum odur.
    final pend = _pending[rel] ?? _inflight[rel];
    final f = _file(rel);
    String text;
    if (pend != null) {
      text = pend;
    } else {
      if (!await f.exists()) return null;
      try {
        text = await f.readAsString();
      } on FileSystemException catch (e) {
        throw StoreCorruptException(rel, 'Okunamadı: ${e.message}');
      }
    }
    try {
      final j = jsonDecode(text);
      if (j is! Map<String, dynamic>) {
        throw const FormatException('Kök nesne değil');
      }
      return j;
    } on FormatException catch (e) {
      throw StoreCorruptException(rel, e.message);
    }
  }

  Future<List<String>> list(String dirRel) async {
    final d = Directory('${root.path}/$dirRel');
    if (!await d.exists()) return [];
    final names = <String>{
      await for (final e in d.list())
        if (e is File && e.path.endsWith('.json'))
          e.uri.pathSegments.last.replaceAll('.json', ''),
    };
    for (final k in _pending.keys) {
      if (k.startsWith('$dirRel/')) {
        names.add(k.substring(dirRel.length + 1).replaceAll('.json', ''));
      }
    }
    return names.toList()..sort();
  }

  /// Kuyruğa yazar (ana iş parçacığını bekletmez). En son çağrı kazanır.
  void writeJson(String rel, Object json) {
    _pending[rel] = jsonEncode(json);
    _kick();
  }

  void _kick() {
    _drain ??= _run().whenComplete(() {
      _drain = null;
      // Döngü bittikten hemen sonra gelen bir yazma kaçmasın.
      if (_pending.isNotEmpty && saveError.value == null) _kick();
    });
  }

  Future<void> _run() async {
    while (_pending.isNotEmpty) {
      final rel = _pending.keys.first;
      final content = _pending.remove(rel)!;
      _inflight[rel] = content;
      try {
        final f = _file(rel);
        await f.parent.create(recursive: true);
        await _atomicWrite(f, content);
        _inflight.remove(rel);
        if (_pending.isEmpty) saveError.value = null;
      } on Object catch (e) {
        // Yeni bir durum gelmediyse bekleyen veriyi koru ve bildir.
        _inflight.remove(rel);
        _pending.putIfAbsent(rel, () => content);
        saveError.value = 'İlerleme kaydedilemedi: $e';
        return;
      }
    }
  }

  Future<void> _atomicWrite(File f, String content) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }

  /// Bekleyen tüm yazmaların bitmesini bekler (arka plana geçerken kullanılır).
  Future<void> flush() async {
    // Yazma hatası varsa (bekleyenler korunur) sonsuza dek beklenmez.
    for (var i = 0; i < 1000; i++) {
      if (_drain == null && (_pending.isEmpty || saveError.value != null)) {
        return;
      }
      _kick();
      await _drain;
    }
  }

  /// Başarısız yazmaları yeniden dener. Başarılıysa true.
  Future<bool> retry() async {
    saveError.value = null;
    _kick();
    await flush();
    return saveError.value == null;
  }

  /// Açık kullanıcı eyleminden sonra (ör. onaylı sıfırlama) dosyayı siler.
  Future<void> delete(String rel) async {
    _pending.remove(rel);
    await flush();
    final f = _file(rel);
    if (await f.exists()) await f.delete();
  }

  /// Bozuk dosyayı silmeden `quarantine/` altına taşır.
  Future<void> quarantine(String rel) async {
    _pending.remove(rel);
    final f = _file(rel);
    if (!await f.exists()) return;
    final name = rel.replaceAll('/', '__');
    final target = _file(
      'quarantine/$name.${DateTime.now().millisecondsSinceEpoch}',
    );
    await f.rename(target.path);
  }

  Future<List<String>> quarantined() async {
    final d = Directory('${root.path}/quarantine');
    if (!await d.exists()) return [];
    return [await for (final e in d.list()) e.uri.pathSegments.last];
  }
}
