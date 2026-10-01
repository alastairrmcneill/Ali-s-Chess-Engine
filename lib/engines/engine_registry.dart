import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v1/v1_engine.dart';

Map<String, ChessEngine Function()> engineRegistry = {
  "v1": () => V1Engine(),
};

ChessEngine createEngine(String name) {
  if (!engineRegistry.containsKey(name)) {
    throw ArgumentError("Engine not found: $name");
  }
  return engineRegistry[name]!();
}

/// Static view of [engineRegistry] for tests and tooling that need every known version id.
class EngineRegistry {
  static List<String> get versionIds => engineRegistry.keys.toList();

  static ChessEngine create(String id) => createEngine(id);
}
