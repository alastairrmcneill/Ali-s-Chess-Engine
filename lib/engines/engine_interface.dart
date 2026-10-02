class SearchLimits {
  final Duration moveTime;

  const SearchLimits({required this.moveTime});
}

class EngineMoveResult {
  final String uciMove; // e.g. e2e4, e7e8q
  final int? evaluation; // centipawns, positive = good for White
  final int? depth; // deepest completed iterative-deepening depth
  final int? nodes; // number of nodes searched

  const EngineMoveResult({
    required this.uciMove,
    this.evaluation,
    this.depth,
    this.nodes,
  });
}

abstract class ChessEngine {
  /// Short id used on the CLI and in the app picker, e.g. "v1".
  String get id;

  /// Human-readable name, used in PGN headers, e.g. "ACE v1".
  String get displayName;

  /// Called before every game. Clear transposition tables, history, etc.
  Future<void> newGame();

  /// [startingFen] is where the game started; [uciMoves] is every move since, oldest first.
  /// Throwing, or returning a move the referee rejects, loses the game.
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits);

  /// Perft from [fen] to [depth] using this version's own move generator.
  int perft(String fen, int depth);
}
