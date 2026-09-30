import 'package:ace/chess_core/fen.dart';

/// The contract every engine version implements so the match manager, the app and the inspector can talk to it.
///
/// It mirrors the UCI protocol: the position is a start FEN plus the moves played since (`position fen ... moves ...`),
/// the limit is a fixed think time (`go movetime`), and the answer is a best move in UCI notation plus search info.
/// Engines only exchange strings, so each version is free to use its own board representation internally, and an
/// external UCI engine (e.g. Stockfish running as a process) could implement this later.
abstract class ChessEngine {
  /// Registry id, e.g. "v1"
  String get id;

  /// Display name used in PGNs and the UI, e.g. "ACE v1"
  String get name;

  /// Called before each new game so the engine can clear anything it keeps between moves
  void newGame() {}

  Future<SearchResult> search(EnginePosition position, SearchLimits limits);
}

class EnginePosition {
  final String startFen;
  final List<String> uciMoves;

  const EnginePosition({this.startFen = FenPosition.startingFen, this.uciMoves = const []});
}

class SearchLimits {
  final int moveTimeMs;

  const SearchLimits({required this.moveTimeMs});
}

class SearchResult {
  /// Best move in UCI notation, or null if the engine failed to find one
  final String? bestMove;

  /// Evaluation in centipawns from the side to move's point of view (null when a mate score is reported)
  final int? scoreCp;

  /// Moves until mate: positive when the side to move mates, negative when it gets mated
  final int? mateIn;

  /// Deepest fully completed search depth
  final int? depth;

  final int? nodes;

  /// The line the engine expects, starting with its best move (UCI notation)
  final List<String> pv;

  final int timeMs;

  const SearchResult({
    required this.bestMove,
    this.scoreCp,
    this.mateIn,
    this.depth,
    this.nodes,
    this.pv = const [],
    required this.timeMs,
  });

  /// Score in centipawns with mates mapped to large values, handy for comparing and sorting
  int? get comparableScore {
    if (mateIn != null) return mateIn! > 0 ? 100000 - mateIn! : -100000 - mateIn!;
    return scoreCp;
  }

  /// e.g. "+0.45", "-1.20", "#3", "#-2"
  String get scoreText {
    if (mateIn != null) return "#$mateIn";
    if (scoreCp == null) return "?";
    String pawns = (scoreCp!.abs() / 100).toStringAsFixed(2);
    return scoreCp! < 0 ? "-$pawns" : "+$pawns";
  }
}
