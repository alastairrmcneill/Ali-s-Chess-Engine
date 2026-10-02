import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/random/random_engine.dart';
import 'package:ace/engines/v1/v1_engine.dart';

class EngineRegistry {
  /// Real engine versions, ordered oldest → newest. Add a line per new version.
  static final Map<String, ChessEngine Function()> _versions = {
    'v1': () => V1Engine(),
  };

  /// Engines used only for testing the harness.
  static final Map<String, ChessEngine Function()> _testEngines = {
    'random': () => RandomEngine(),
  };

  /// For the app's version picker.
  static List<String> get versionIds => _versions.keys.toList();

  /// For the CLI.
  static List<String> get allIds => [..._versions.keys, ..._testEngines.keys];

  static String get latestId => _versions.keys.last;

  /// Always returns a NEW instance, which is required for v1-vs-v1 matches.
  static ChessEngine create(String id) {
    final factory = _versions[id] ?? _testEngines[id];
    if (factory == null) {
      throw ArgumentError('Unknown engine "$id". Known: ${allIds.join(', ')}');
    }
    return factory();
  }
}
