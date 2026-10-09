class SearchLimits {
  final Duration moveTime;

  /// Fixed search depth. When set, engines that support it search exactly this deep and ignore [moveTime].
  final int? depth;

  SearchLimits({required this.moveTime, this.depth});
}

/// What one iterative deepening step concluded, plus the engine's counters at that point.
/// Engine-agnostic: plain ints and UCI strings only.
class SearchStats {
  int? depth = 0; // iterative deepening depth this step searched
  int nodes = 0;
  int qNodes = 0;
  int transpositions = 0;
  int maxQDepth = 0;
  int evaluations = 0;
  int betaCutoffs = 0;
  int qBetaCutoffs = 0;
  int qCheckNodes = 0; // quiescence nodes where the side to move was in check
  int firstMoveCutoffs = 0; // beta cutoffs where the first move tried was the cutting one  = 0; measures move ordering
  int? eval = 0; // centipawns from the side to move's point of view
  String? bestMove = ''; // UCI
  List<String> pv = const []; // UCI, best effort; may be empty
  Duration elapsed = Duration.zero; // since the search started
  bool aborted = false; // the step ran out of time before finishing

  SearchStats({
    this.depth = 0,
    this.nodes = 0,
    this.qNodes = 0,
    this.transpositions = 0,
    this.maxQDepth = 0,
    this.evaluations = 0,
    this.betaCutoffs = 0,
    this.qBetaCutoffs = 0,
    this.qCheckNodes = 0,
    this.firstMoveCutoffs = 0,
    this.eval = 0,
    this.bestMove = '',
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
        betaCutoffs: json['betaCutoffs'] as int? ?? 0,
        qBetaCutoffs: json['qBetaCutoffs'] as int? ?? 0,
        qCheckNodes: json['qCheckNodes'] as int? ?? 0,
        firstMoveCutoffs: json['firstMoveCutoffs'] as int? ?? 0,
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
        'betaCutoffs': betaCutoffs,
        'qBetaCutoffs': qBetaCutoffs,
        'qCheckNodes': qCheckNodes,
        'firstMoveCutoffs': firstMoveCutoffs,
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
  final SearchStats? stats; // counters for the whole search, when the engine collects them

  EngineMoveResult({
    required this.uciMove,
    this.evaluation,
    this.depth,
    this.nodes,
    this.principalVariation,
    this.stats,
  });
}

abstract class ChessEngine {
  String get id;

  String get displayName;

  void newGame();

  /// Blocks until the search is done. Engines that search iteratively call [onSearchProgressUpdate] after each step.
  EngineMoveResult getMove(
    String startingFen,
    List<String> uciMoves,
    SearchLimits limits, {
    SearchProgressCallback? onSearchProgressUpdate,
  });

  PerftTestResult perft(String fen, int depth);
}

class PerftTestResult {
  int nodes;
  int? captures;

  PerftTestResult(this.nodes, {this.captures});
}
