import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/puzzle.dart';
import '../domain/validator.dart';

/// Paketlenmiş içerik havuzu. Geçersiz bulmacalar havuza alınmaz ve
/// [rejected] içinde nedenleriyle listelenir.
class ContentLibrary {
  ContentLibrary(List<PuzzleDefinition> puzzles, this.rejected)
    : puzzles = List.of(puzzles),
      _byId = {for (final p in puzzles) p.id: p};

  final List<PuzzleDefinition> puzzles;
  final List<String> rejected;
  final Map<String, PuzzleDefinition> _byId;

  /// Cihazda üretilen (ör. Sudoku) bulmacayı havuza ekler. Kimlik çakışırsa
  /// eklenmez.
  bool add(PuzzleDefinition p) {
    if (_byId.containsKey(p.id)) return false;
    puzzles.add(p);
    _byId[p.id] = p;
    return true;
  }

  PuzzleDefinition? byId(String id) => _byId[id];

  List<PuzzleDefinition> ofType(PuzzleType t) =>
      puzzles.where((p) => p.type == t).toList();

  /// JSON metinlerinden havuz kurar; bozuk veya geçersiz kayıtları ayıklar.
  static ContentLibrary fromJsonDocuments(
    Iterable<String> docs, {
    bool deep = true,
  }) {
    final ok = <PuzzleDefinition>[];
    final rejected = <String>[];
    final ids = <String>{};
    for (final doc in docs) {
      Object? decoded;
      try {
        decoded = jsonDecode(doc);
      } on FormatException catch (e) {
        rejected.add('Geçersiz JSON: ${e.message}');
        continue;
      }
      final list = decoded is List ? decoded : [decoded];
      for (final item in list) {
        try {
          if (item is! Map<String, dynamic>) {
            throw ContentException('Bulmaca kaydı bir nesne olmalı');
          }
          final p = PuzzleDefinition.fromJson(item);
          final errors = ContentValidator.validate(p, deep: deep);
          if (errors.isNotEmpty) {
            rejected.addAll(errors);
          } else if (!ids.add(p.id)) {
            rejected.add('Yinelenen bulmaca kimliği: ${p.id}');
          } else {
            ok.add(p);
          }
        } on ContentException catch (e) {
          rejected.add(e.message);
        } on Object catch (e) {
          rejected.add('Okunamayan bulmaca kaydı: $e');
        }
      }
    }
    return ContentLibrary(ok, rejected);
  }

  static Future<ContentLibrary> loadAssets(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final paths =
        manifest
            .listAssets()
            .where(
              (p) => p.startsWith('assets/puzzles/') && p.endsWith('.json'),
            )
            .toList()
          ..sort();
    final docs = await Future.wait([
      for (final p in paths) bundle.loadString(p),
    ]);
    // Çalışma anında hafif doğrulama; tam doğrulama test_content ile yapılır.
    return fromJsonDocuments(docs, deep: false);
  }
}
