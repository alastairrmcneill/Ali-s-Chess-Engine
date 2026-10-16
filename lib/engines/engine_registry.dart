import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v0/v0_engine.dart';
import 'package:ace/engines/v1/v1_engine.dart';
import 'package:ace/engines/v10/v10_engine.dart';
import 'package:ace/engines/v11/v11_engine.dart';
import 'package:ace/engines/v2/v2_engine.dart';
import 'package:ace/engines/v3/v3_engine.dart';
import 'package:ace/engines/v4/v4_engine.dart';
import 'package:ace/engines/v5/v5_engine.dart';
import 'package:ace/engines/v6/v6_engine.dart';
import 'package:ace/engines/v7/v7_engine.dart';
import 'package:ace/engines/v8/v8_engine.dart';
import 'package:ace/engines/v9/v9_engine.dart';

class EngineRegistry {
  /// Real engine versions, ordered oldest → newest. Add a line per new version.
  static final Map<String, ChessEngine Function()> _versions = {
    'v0': () => V0Engine(),
    'v1': () => V1Engine(),
    'v2': () => V2Engine(),
    'v3': () => V3Engine(),
    'v4': () => V4Engine(),
    'v5': () => V5Engine(),
    'v6': () => V6Engine(),
    'v7': () => V7Engine(),
    'v8': () => V8Engine(),
    'v9': () => V9Engine(),
    'v10': () => V10Engine(),
    'v11': () => V11Engine(),
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
