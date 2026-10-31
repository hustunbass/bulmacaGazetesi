import 'dart:io';

import 'package:bulmaca_postasi/data/file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FileStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fs_test');
    store = FileStore(dir);
    await store.init();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // geçici dizin
    }
  });

  test('yazma sürerken okuma en yeni durumu görür', () async {
    store.writeJson('attempts/a.json', {'n': 1});
    final r = await store.readJson('attempts/a.json');
    expect(r, {'n': 1});
    store.writeJson('attempts/a.json', {'n': 2});
    expect((await store.readJson('attempts/a.json'))!['n'], 2);
    await store.flush();
  });

  test(
    'flush, ardışık yazmaların hepsinin diske indiğini garanti eder',
    () async {
      for (var i = 0; i < 200; i++) {
        store.writeJson('attempts/x${i % 7}.json', {'i': i});
      }
      await store.flush();
      final fresh = FileStore(dir);
      for (var k = 0; k < 7; k++) {
        var last = 0;
        for (var i = 0; i < 200; i++) {
          if (i % 7 == k) last = i;
        }
        expect((await fresh.readJson('attempts/x$k.json'))!['i'], last);
      }
    },
  );

  test('flush beklenirken gelen yazma da diske iner', () async {
    store.writeJson('attempts/y.json', {'v': 1});
    final f = store.flush();
    store.writeJson('attempts/y.json', {'v': 2});
    await f;
    await store.flush();
    final fresh = FileStore(dir);
    expect((await fresh.readJson('attempts/y.json'))!['v'], 2);
  });

  test('yazma hatasında flush sonsuza dek beklemez; veri korunur', () async {
    Directory('${dir.path}/attempts').deleteSync(recursive: true);
    File('${dir.path}/attempts').writeAsStringSync('engel');
    store.writeJson('attempts/z.json', {'v': 1});
    await store.flush().timeout(const Duration(seconds: 5));
    expect(store.saveError.value, isNotNull);
    expect(
      (await store.readJson('attempts/z.json'))!['v'],
      1,
      reason: 'bekleyen veri okunabilir kalır',
    );
    File('${dir.path}/attempts').deleteSync();
    Directory('${dir.path}/attempts').createSync();
    expect(await store.retry(), isTrue);
  });
}
