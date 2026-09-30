import 'package:ace/engines/chess_engine.dart';
import 'package:ace/engines/v1/v1_engine.dart';
import 'package:ace/engines/v2/v2_engine.dart';

/// Every engine version that can play. Add new versions here (tool/new_engine_version.dart does it for you).
/// Engines are created from their id, which lets match worker isolates build their own instances.
final Map<String, ChessEngine Function()> engineRegistry = {
  "v1": () => V1Engine(),
  "v2": () => V2Engine(),
};

/// The version the store app plays against
const String latestEngineId = "v2";

ChessEngine createEngine(String id) {
  ChessEngine Function()? factory = engineRegistry[id];
  if (factory == null) throw ArgumentError("Unknown engine '$id'. Available: ${engineRegistry.keys.join(", ")}");
  return factory();
}
