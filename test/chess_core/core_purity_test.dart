import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _importRegExp = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);

/// chess_core must never depend on an engine (or Flutter); notation/ must be fully self-contained,
/// because every engine version imports it.
void main() {
  final files = Directory('lib/chess_core')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('chess_core has files', () => expect(files, isNotEmpty));

  for (final file in files) {
    final isNotation = file.path.replaceAll('\\', '/').contains('lib/chess_core/notation/');
    final allowedPrefix = isNotation ? 'package:ace/chess_core/notation/' : 'package:ace/chess_core/';

    test('${file.path} only imports dart: or $allowedPrefix', () {
      final imports = _importRegExp.allMatches(file.readAsStringSync()).map((m) => m.group(1)!);
      for (final import in imports) {
        expect(import.startsWith('dart:') || import.startsWith(allowedPrefix), isTrue,
            reason: '${file.path} has a disallowed import: $import');
      }
    });
  }
}
