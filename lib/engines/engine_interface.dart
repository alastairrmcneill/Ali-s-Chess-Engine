class SearchLimits {
  final Duration moveTime;

  SearchLimits({required this.moveTime});
}

/// What one iterative deepening step concluded, plus the engine's counters at that point.
/// Engine-agnostic: plain ints and UCI strings only.
class SearchStats {
  final int? depth; // iterative deepening depth this step searched
  final int nodes;
  final int qNodes;
  final int transpositions;
  final int maxQDepth;
  final int evaluations;
  final int? eval; // centipawns from the side to move's point of view
  final String? bestMove; // UCI
  final List<String> pv; // UCI, best effort; may be empty
  final Duration elapsed; // since the search started
  final bool aborted; // the step ran out of time before finishing

  const SearchStats({
    this.depth,
    required this.nodes,
    required this.qNodes,
    required this.transpositions,
    required this.maxQDepth,
    required this.evaluations,
    this.eval,
    this.bestMove,
    this.pv = const [],
    this.elapsed = Duration.zero,
    this.aborted = false,
  });

  factory SearchStats.fromJson(Map<dynamic, dynamic> json) => SearchStats(
        depth: json['depth'] as int?,
        eval: json['eval'] as int?,
        bestMove: json['bestMove'] as String?,
        pv: List<String>.from(json['pv'] as List),
        nodes: json['nodes'] as int,
        qNodes: json['qNodes'] as int,
        transpositions: json['transpositions'] as int,
        maxQDepth: json['maxQDepth'] as int,
        evaluations: json['evaluations'] as int,
        elapsed: Duration(milliseconds: json['timeMs'] as int),
        aborted: json['aborted'] as bool,
      );

  Map<String, Object?> toJson() => {
        'depth': depth,
        'eval': eval,
        'bestMove': bestMove,
        'pv': pv,
        'nodes': nodes,
        'qNodes': qNodes,
        'transpositions': transpositions,
        'maxQDepth': maxQDepth,
        'evaluations': evaluations,
        'timeMs': elapsed.inMilliseconds,
        'aborted': aborted,
      };
}

/// Optional live progress: engines that search iteratively call it after every step, others never do.
typedef SearchProgressCallback = void Function(SearchStats iteration);

class EngineMoveResult {
  final String uciMove; // e.g. e2e4, e7e8q
  final int? evaluation; // centipawns, positive for white advantage, negative for black advantage
  final int? depth; // last fully completed iterative deepening depth
  final int? nodes; // number of nodes searched by the engine
  final List<String>? principalVariation; // UCI, the line the engine expects to be played

  EngineMoveResult({
    required this.uciMove,
    this.evaluation,
    this.depth,
    this.nodes,
    this.principalVariation,
  });
}

abstract class ChessEngine {
  String get id;

  String get displayName;

  void newGame();

  /// Blocks until the search is done. Engines that search iteratively call [onIteration] after each step.
  EngineMoveResult getMove(
    String startingFen,
    List<String> uciMoves,
    SearchLimits limits, {
    SearchProgressCallback? onIteration,
  });

  int perft(String fen, int depth);
}
