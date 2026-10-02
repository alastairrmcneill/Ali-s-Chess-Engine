import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _importRegExp = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);

void main() {
  final enginesDir = Directory('lib/engines');
  final versionDirs = enginesDir
      .listSync()
      .whereType<Directory>()
      .where((dir) => RegExp(r'^v\d+$').hasMatch(dir.uri.pathSegments.where((s) => s.isNotEmpty).last))
      .toList();

  test('there is at least one lib/engines/v* snapshot folder', () {
    expect(versionDirs, isNotEmpty);
  });

  for (final versionDir in versionDirs) {
    final versionId = versionDir.uri.pathSegments.where((s) => s.isNotEmpty).last;

    group('Snapshot purity: $versionId', () {
      final dartFiles =
          versionDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

      for (final file in dartFiles) {
        test('${file.path} only imports dart:, its own version, or chess_core/notation', () {
          final content = file.readAsStringSync();
          final isAdapter = content.contains('implements ChessEngine');
          final imports = _importRegExp.allMatches(content).map((m) => m.group(1)!);

          for (final import in imports) {
            final allowed = import.startsWith('dart:') ||
                import.startsWith('package:ace/engines/$versionId/') ||
                import.startsWith('package:ace/chess_core/notation/') || // shared standards code only
                (isAdapter && import == 'package:ace/engines/engine_interface.dart');

            expect(
              allowed,
              isTrue,
              reason: '${file.path} has a disallowed import: $import',
            );
          }
        });
      }
    });
  }
}
