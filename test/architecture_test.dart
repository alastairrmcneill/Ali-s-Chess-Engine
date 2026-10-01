import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The engine, rules and match code must not depend on Flutter so it can run from the `dart run` CLI and in
/// background isolates.
void main() {
  const List<String> flutterFreeFolders = ["lib/chess_core", "lib/engines", "lib/match", "lib/analysis"];

  test("engine, rules and match code don't import Flutter", () {
    List<String> offenders = [];
    for (String folder in flutterFreeFolders) {
      Directory directory = Directory(folder);
      if (!directory.existsSync()) continue;
      for (FileSystemEntity file in directory.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith(".dart")) continue;
        if (RegExp(r"import\s+'(package:flutter|dart:ui)").hasMatch(file.readAsStringSync())) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  // Each engine version must be self-contained so changing one can never change another. Several versions (and
  // chess_core) have classes with the same names (Board, Move, MoveGenerator...), and Dart treats them as different
  // types, so a wrong import gives confusing "Board can't be assigned to Board" errors. The only shared code an
  // engine may use is the engine interface and the neutral FEN/UCI parsing, which have no Board or Move types.
  test("engine versions only import their own code", () {
    const List<String> allowedShared = [
      "package:ace/engines/chess_engine.dart",
      "package:ace/chess_core/fen.dart",
      "package:ace/chess_core/uci.dart",
    ];
    List<String> offenders = [];
    for (FileSystemEntity versionFolder in Directory("lib/engines").listSync()) {
      if (versionFolder is! Directory) continue;
      String version = versionFolder.path.split("/").last;
      for (FileSystemEntity file in versionFolder.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith(".dart")) continue;
        for (Match import in RegExp(r"import\s+'([^']+)'").allMatches(file.readAsStringSync())) {
          String uri = import.group(1)!;
          bool ownCode = uri.startsWith("package:ace/engines/$version/");
          bool allowed = ownCode || uri.startsWith("dart:") || allowedShared.contains(uri);
          if (!allowed) offenders.add("${file.path} imports $uri");
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
