import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v1/v1_engine.dart';
import 'package:ace/engines/v0/v0_engine.dart';

class EngineRegistry {
  /// Real engine versions, ordered oldest → newest. Add a line per new version.
  static final Map<String, ChessEngine Function()> _versions = {
    'v0': () => V0Engine(),
    'v1': () => V1Engine(),
  };

  static List<String> get allIds => _versions.keys.toList();

  static String get latestId => _versions.keys.last;

  /// Always returns a NEW instance, which is required for v1-vs-v1 matches.
  static ChessEngine create(String id) {
    final factory = _versions[id];
    if (factory == null) {
      throw ArgumentError('Unknown engine "$id". Known: ${allIds.join(', ')}');
    }
    return factory();
  }
}
