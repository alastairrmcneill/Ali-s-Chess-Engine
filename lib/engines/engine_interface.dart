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

/// A snapshot of an engine's search counters, read while it is still thinking.
class SearchStats {
  final int? depth; // iterative deepening depth currently being searched
  final int nodes;
  final int qNodes;
  final int transpositions;
  final int maxQDepth;
  final int evaluations;
  final int? eval; // centipawns from the side to move's point of view, as of the last completed depth
  final String? bestMove; // UCI, as of the last completed depth
  final Duration elapsed;

  const SearchStats({
    this.depth,
    required this.nodes,
    required this.qNodes,
    required this.transpositions,
    required this.maxQDepth,
    required this.evaluations,
    this.eval,
    this.bestMove,
    this.elapsed = Duration.zero,
  });

  SearchStats copyWith({int? depth, Duration? elapsed}) => SearchStats(
        depth: depth ?? this.depth,
        nodes: nodes,
        qNodes: qNodes,
        transpositions: transpositions,
        maxQDepth: maxQDepth,
        evaluations: evaluations,
        eval: eval,
        bestMove: bestMove,
        elapsed: elapsed ?? this.elapsed,
      );
}

/// Implemented by engines that can report [SearchStats] while a search is running.
abstract class LiveStatsEngine {
  SearchStats? get liveStats;
}
