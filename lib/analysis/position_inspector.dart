import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/fen.dart';
import 'package:ace/chess_core/game_result.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/move_generator.dart';
import 'package:ace/chess_core/san.dart';
import 'package:ace/chess_core/uci.dart';
import 'package:ace/engines/chess_engine.dart';
import 'package:ace/engines/engine_registry.dart';

class CandidateMove {
  final String uci;
  final String san;
  final int? scoreCp; // From the point of view of the side playing the move
  final int? mateIn; // Positive: this side mates, negative: this side gets mated
  final int? depth;
  final List<String> lineSan; // The move followed by the engine's expected continuation
  final String? note; // e.g. "checkmate" or "stalemate" when the move ends the game

  const CandidateMove({
    required this.uci,
    required this.san,
    this.scoreCp,
    this.mateIn,
    this.depth,
    this.lineSan = const [],
    this.note,
  });

  int get comparableScore {
    if (mateIn != null) return mateIn! > 0 ? 100000 - mateIn! : -100000 - mateIn!;
    return scoreCp ?? -200000;
  }

  String get scoreText {
    if (mateIn != null) return "#$mateIn";
    if (scoreCp == null) return "?";
    String pawns = (scoreCp!.abs() / 100).toStringAsFixed(2);
    return scoreCp! < 0 ? "-$pawns" : "+$pawns";
  }

  Map<String, dynamic> toJson() => {
        "uci": uci,
        "san": san,
        "scoreCp": scoreCp,
        "mateIn": mateIn,
        "depth": depth,
        "line": lineSan,
        "note": note,
      };

  factory CandidateMove.fromJson(Map<String, dynamic> json) => CandidateMove(
        uci: json["uci"],
        san: json["san"],
        scoreCp: json["scoreCp"],
        mateIn: json["mateIn"],
        depth: json["depth"],
        lineSan: (json["line"] as List).cast<String>(),
        note: json["note"],
      );
}

/// Ranks every legal move in a position with any engine version, to see what it thinks the best few moves are.
///
/// Alpha-beta search only computes an exact score for the best move, so to get a proper top N the inspector plays
/// each legal move itself and asks the engine to search the resulting position. The engine is used as a black box
/// through [ChessEngine], so this works for every version without changing any engine code.
class PositionInspector {
  /// Returns all legal moves, best first. [onProgress] is called after each move is analysed.
  static Future<List<CandidateMove>> analyse({
    required String engineId,
    String startFen = FenPosition.startingFen,
    List<String> uciMoves = const [],
    int msPerCandidate = 300,
    void Function(int done, int total)? onProgress,
  }) async {
    Board board = Board.fromFen(startFen);
    for (String uci in uciMoves) {
      board.makeMove(Uci.toLegalMove(board, uci) ?? (throw ArgumentError("Illegal move $uci")));
    }

    ChessEngine engine = createEngine(engineId);
    engine.newGame();
    List<Move> legalMoves = MoveGenerator().generateLegalMoves(board);
    List<CandidateMove> candidates = [];

    for (Move move in legalMoves) {
      String uci = move.toChessNotation();
      String san = San.fromMove(board, move);
      board.makeMove(move);

      Result result = GameResult.check(board);
      if (result == Result.whiteIsMated || result == Result.blackIsMated) {
        candidates.add(CandidateMove(uci: uci, san: san, mateIn: 1, lineSan: [san], note: "checkmate"));
      } else if (result != Result.playing) {
        candidates.add(CandidateMove(uci: uci, san: san, scoreCp: 0, lineSan: [san], note: result.name));
      } else {
        SearchResult reply = await engine.search(
          EnginePosition(startFen: startFen, uciMoves: [...uciMoves, uci]),
          SearchLimits(moveTimeMs: msPerCandidate),
        );
        // The reply's score is from the opponent's point of view, so flip it
        int? mateIn;
        if (reply.mateIn != null) mateIn = reply.mateIn! > 0 ? -reply.mateIn! : -reply.mateIn! + 1;
        candidates.add(CandidateMove(
          uci: uci,
          san: san,
          scoreCp: reply.scoreCp == null ? null : -reply.scoreCp!,
          mateIn: mateIn,
          depth: reply.depth,
          lineSan: [san, ..._lineToSan(board, reply.pv)],
        ));
      }

      board.unMakeMove(move);
      onProgress?.call(candidates.length, legalMoves.length);
    }

    candidates.sort((a, b) => b.comparableScore.compareTo(a.comparableScore));
    return candidates;
  }

  static List<String> _lineToSan(Board board, List<String> line) {
    List<String> sans = [];
    List<Move> played = [];
    for (String uci in line) {
      Move? move = Uci.toLegalMove(board, uci);
      if (move == null) break;
      sans.add(San.fromMove(board, move));
      board.makeMove(move);
      played.add(move);
    }
    for (Move move in played.reversed) {
      board.unMakeMove(move);
    }
    return sans;
  }
}
