class SearchLimits {
  final Duration moveTime;

  SearchLimits({required this.moveTime});
}

class EngineMoveResult {
  final String uciMove; // e.g. e2e4, e7e8q
  final int? evaluation; // centipawns, positive for white advantage, negative for black advantage
  final int? depth; // search depth reached by the engine
  final int? nodes; // number of nodes searched by the engine

  EngineMoveResult({
    required this.uciMove,
    this.evaluation,
    this.depth,
    this.nodes,
  });
}

abstract class ChessEngine {
  String get id;

  String get displayName;

  Future<void> newGame();

  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits);

  int perft(String fen, int depth);
}
