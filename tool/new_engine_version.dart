// Starts a new engine version by copying an existing one.
//
//   dart run tool/new_engine_version.dart v2            (copies the latest version)
//   dart run tool/new_engine_version.dart v3 --from v1
//
// It copies lib/engines/<from> to lib/engines/<new>, points the copy's imports at itself, renames the adapter
// (e.g. V1Engine -> V2Engine, "ACE v1" -> "ACE v2"), registers it in lib/engines/engine_registry.dart and makes it
// the version the store app plays. The old version is left untouched, so it keeps playing exactly as before.
import 'dart:io';

import 'package:ace/engines/engine_registry.dart';

void main(List<String> args) {
  if (args.isEmpty || args.length == 2 || (args.length == 3 && args[1] != "--from")) {
    stderr.writeln("Usage: dart run tool/new_engine_version.dart <new id> [--from <existing id>]");
    exit(64);
  }
  String newId = args[0];
  String fromId = args.length == 3 ? args[2] : latestEngineId;

  if (!RegExp(r"^[a-z][a-z0-9_]*$").hasMatch(newId)) {
    stderr.writeln("Use a lowercase id like v2 (letters, digits and underscores)");
    exit(64);
  }
  Directory from = Directory("lib/engines/$fromId");
  Directory to = Directory("lib/engines/$newId");
  if (!from.existsSync()) {
    stderr.writeln("${from.path} doesn't exist (run this from the project root)");
    exit(1);
  }
  if (to.existsSync() || engineRegistry.containsKey(newId)) {
    stderr.writeln("$newId already exists");
    exit(1);
  }

  String fromClass = "${fromId[0].toUpperCase()}${fromId.substring(1)}Engine";
  String newClass = "${newId[0].toUpperCase()}${newId.substring(1)}Engine";

  for (FileSystemEntity entity in from.listSync(recursive: true)) {
    if (entity is! File) continue;
    String relative = entity.path.substring(from.path.length + 1);
    bool isAdapter = relative == "${fromId}_engine.dart";
    File target = File("${to.path}/${isAdapter ? "${newId}_engine.dart" : relative}");
    target.parent.createSync(recursive: true);

    String content = entity.readAsStringSync().replaceAll("package:ace/engines/$fromId/", "package:ace/engines/$newId/");
    if (isAdapter) {
      content = content
          .replaceAll(fromClass, newClass)
          .replaceAll('get id => "$fromId"', 'get id => "$newId"')
          .replaceAll(RegExp('get name => "ACE $fromId"'), 'get name => "ACE $newId"');
    }
    target.writeAsStringSync(content);
  }

  // Register the new version and make it the one the store app plays
  File registry = File("lib/engines/engine_registry.dart");
  String source = registry.readAsStringSync();
  source = source.replaceFirst(
    "import 'package:ace/engines/$fromId/${fromId}_engine.dart';",
    "import 'package:ace/engines/$fromId/${fromId}_engine.dart';\n"
        "import 'package:ace/engines/$newId/${newId}_engine.dart';",
  );
  source = source.replaceFirstMapped(
    RegExp(r"(final Map<String, ChessEngine Function\(\)> engineRegistry = \{\n(?:  .*\n)*)\};"),
    (match) => '${match.group(1)}  "$newId": () => $newClass(),\n};',
  );
  source = source.replaceFirst(RegExp(r'const String latestEngineId = "[^"]*";'), 'const String latestEngineId = "$newId";');
  registry.writeAsStringSync(source);

  stdout.writeln("Created ${to.path} from ${from.path} and registered \"$newId\" as the latest engine.");
  stdout.writeln("Make your improvements in ${to.path}, then compare:");
  stdout.writeln("  dart run bin/match.dart --engine1 $newId --engine2 $fromId");
}
