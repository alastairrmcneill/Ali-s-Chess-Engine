import 'package:ace/engines/engine_interface.dart';

/// Base class for test engines.
abstract class FakeEngine implements ChessEngine {
  @override
  final String id;
  int newGameCalls = 0;
  int getMoveCalls = 0;

  FakeEngine(this.id);

  @override
  String get displayName => 'Fake $id';

  @override
  Future<void> newGame() async => newGameCalls++;

  @override
  int perft(String fen, int depth) => throw UnsupportedError('fake engine');

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async {
    getMoveCalls++;
    return EngineMoveResult(uciMove: nextMove(uciMoves), evaluation: 0, depth: 1, nodes: 1);
  }

  String nextMove(List<String> uciMoves);
}

/// Plays the given moves in order, one per call (restarting each game).
class ScriptedEngine extends FakeEngine {
  final List<String> moves;
  int _next = 0;

  ScriptedEngine(this.moves, [String id = 'scripted']) : super(id);

  @override
  Future<void> newGame() async {
    _next = 0;
    await super.newGame();
  }

  @override
  String nextMove(List<String> uciMoves) => moves[_next++];
}

class IllegalEngine extends FakeEngine {
  IllegalEngine() : super('illegal');

  @override
  String nextMove(List<String> uciMoves) => 'e2e5';
}

class MalformedEngine extends FakeEngine {
  MalformedEngine() : super('malformed');

  @override
  String nextMove(List<String> uciMoves) => 'xyz';
}

class NoMoveEngine extends FakeEngine {
  NoMoveEngine() : super('nomove');

  @override
  String nextMove(List<String> uciMoves) => '';
}

class CrashingEngine extends FakeEngine {
  CrashingEngine() : super('crashing');

  @override
  String nextMove(List<String> uciMoves) => throw Exception('boom');
}

/// Tries to change the history it was given.
class TamperingEngine extends FakeEngine {
  TamperingEngine() : super('tampering');

  @override
  String nextMove(List<String> uciMoves) {
    uciMoves.add('e2e4');
    return 'e2e4';
  }
}
