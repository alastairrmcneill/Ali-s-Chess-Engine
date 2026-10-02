import 'dart:io';

/// Creates a new engine version by copying an existing one.
///
///   dart run tool/snapshot_engine.dart v1 v2
///
/// Copies lib/engines/v1 → lib/engines/v2, rewrites `package:ace/engines/v1/` imports, and renames the
/// adapter (v1_engine.dart / V1Engine / id 'v1' / 'ACE v1'). Shared chess_core/notation imports are left alone.
/// Then add the new version to lib/engines/engine_registry.dart.
void main(List<String> args) {
  if (args.length != 2 || !RegExp(r'^v\d+$').hasMatch(args[0]) || !RegExp(r'^v\d+$').hasMatch(args[1])) {
    stderr.writeln('Usage: dart run tool/snapshot_engine.dart <from> <to>   e.g. v1 v2');
    exit(64);
  }
  final from = args[0], to = args[1];
  final source = Directory('lib/engines/$from');
  final destination = Directory('lib/engines/$to');
  if (!source.existsSync()) _fail('${source.path} does not exist');
  if (destination.existsSync()) _fail('${destination.path} already exists');

  final fromClass = 'V${from.substring(1)}Engine', toClass = 'V${to.substring(1)}Engine';
  var files = 0, rewrites = 0;

  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    var relative = entity.path.substring(source.path.length + 1);
    var content = entity.readAsStringSync();
    final before = content;

    content = content.replaceAll('package:ace/engines/$from/', 'package:ace/engines/$to/');
    if (relative == '${from}_engine.dart') {
      relative = '${to}_engine.dart';
      content = content
          .replaceAll(fromClass, toClass)
          .replaceAll("=> '$from';", "=> '$to';")
          .replaceAll("'ACE $from'", "'ACE $to'");
    }
    if (content != before) rewrites++;

    File('${destination.path}/$relative')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    files++;
  }

  stdout.writeln('Copied $files files to ${destination.path} ($rewrites rewritten).');
  stdout.writeln('Now add this to EngineRegistry._versions in lib/engines/engine_registry.dart:');
  stdout.writeln("    '$to': () => $toClass(),   // import 'package:ace/engines/$to/${to}_engine.dart';");
}

Never _fail(String message) {
  stderr.writeln('Error: $message');
  exit(1);
}
