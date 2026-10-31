import 'dart:convert';
import 'dart:io';

import 'package:bulmaca_postasi/data/content_library.dart';
import 'package:bulmaca_postasi/domain/puzzle.dart';

/// Paketlenmiş içeriği doğrudan diskten okur (testler Flutter varlık
/// paketine ihtiyaç duymaz).
ContentLibrary loadLibraryFromDisk() {
  final docs = [
    for (final f in Directory('assets/puzzles').listSync().whereType<File>())
      if (f.path.endsWith('.json')) f.readAsStringSync(),
  ];
  return ContentLibrary.fromJsonDocuments(docs);
}

PuzzleDefinition puzzle(String id) => loadLibraryFromDisk().byId(id)!;

PuzzleDefinition firstOf(PuzzleType t) => loadLibraryFromDisk().ofType(t).first;

List<dynamic> decode(String s) => jsonDecode(s) as List;
