import 'dart:math';

import 'package:ace/chess_core/referee.dart';
import 'package:ace/engines/engine_interface.dart';

/// Plays a random legal move. Used to sanity-check the match harness (any real engine should crush it).
class RandomEngine implements ChessEngine {
  final Random _random;

  RandomEngine({int? seed}) : _random = Random(seed);

  @override
  String get id => 'random';

  @override
  String get displayName => 'Random mover';

  @override
  Future<void> newGame() async {}

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async {
    final referee = Referee(startingFen, maxPlies: 1 << 30);
    for (final move in uciMoves) {
      final reason = referee.tryPlayUci(move);
      if (reason != null) throw StateError(reason);
    }
    final legal = referee.legalUciMoves();
    if (legal.isEmpty) throw StateError('no legal moves');
    return EngineMoveResult(uciMove: legal[_random.nextInt(legal.length)]);
  }

  @override
  int perft(String fen, int depth) => throw UnsupportedError('RandomEngine has no move generator of its own');
}
