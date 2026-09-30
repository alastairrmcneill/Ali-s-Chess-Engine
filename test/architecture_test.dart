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
}
