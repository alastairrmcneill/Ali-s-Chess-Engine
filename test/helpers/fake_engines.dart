import 'package:ace/engines/engine_interface.dart';

/// Returns the next move from a fixed script each time [getMove] is called.
/// Throws if asked for more moves than were scripted.
class ScriptedEngine implements ChessEngine {
  final List<String> moves;
  int _next = 0;

  ScriptedEngine(this.moves);

  @override
  String get id => 'scripted';

  @override
  String get displayName => 'Scripted';

  @override
  Future<void> newGame() async => _next = 0;

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async {
    if (_next >= moves.length) {
      throw StateError('ScriptedEngine ran out of scripted moves');
    }
    return EngineMoveResult(uciMove: moves[_next++]);
  }

  @override
  int perft(String fen, int depth) => 0;
}

/// Always returns a move that is never legal (a piece can't move to its own square).
class IllegalEngine implements ChessEngine {
  @override
  String get id => 'illegal';

  @override
  String get displayName => 'Illegal';

  @override
  Future<void> newGame() async {}

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async =>
      EngineMoveResult(uciMove: 'a1a1');

  @override
  int perft(String fen, int depth) => 0;
}

/// Always throws, simulating an engine crash.
class CrashingEngine implements ChessEngine {
  @override
  String get id => 'crashing';

  @override
  String get displayName => 'Crashing';

  @override
  Future<void> newGame() async {}

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async {
    throw Exception('boom');
  }

  @override
  int perft(String fen, int depth) => 0;
}

/// Returns text that doesn't look like a UCI move at all.
class MalformedEngine implements ChessEngine {
  @override
  String get id => 'malformed';

  @override
  String get displayName => 'Malformed';

  @override
  Future<void> newGame() async {}

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async =>
      EngineMoveResult(uciMove: 'xyz');

  @override
  int perft(String fen, int depth) => 0;
}

/// Returns an empty move string.
class NoMoveEngine implements ChessEngine {
  @override
  String get id => 'no-move';

  @override
  String get displayName => 'No move';

  @override
  Future<void> newGame() async {}

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async =>
      EngineMoveResult(uciMove: '');

  @override
  int perft(String fen, int depth) => 0;
}

/// Wraps another engine and counts how many times each method is called.
class CountingEngine implements ChessEngine {
  final ChessEngine inner;
  int newGameCalls = 0;
  int getMoveCalls = 0;

  CountingEngine(this.inner);

  @override
  String get id => inner.id;

  @override
  String get displayName => inner.displayName;

  @override
  Future<void> newGame() async {
    newGameCalls++;
    await inner.newGame();
  }

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async {
    getMoveCalls++;
    return inner.getMove(startingFen, uciMoves, limits);
  }

  @override
  int perft(String fen, int depth) => inner.perft(fen, depth);
}
