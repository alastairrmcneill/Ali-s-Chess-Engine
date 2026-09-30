import 'dart:async';

import 'package:ace/chess_core/uci.dart';
import 'package:ace/engines/chess_engine.dart';
import 'package:ace/engines/v1/ai/engine.dart';
import 'package:ace/engines/v1/ai/transposition_table.dart';
import 'package:ace/engines/v1/core/board.dart';
import 'package:ace/engines/v1/core/move.dart';
import 'package:ace/engines/v1/core/move_generator.dart';
import 'package:ace/engines/v1/core/piece.dart';
import 'package:ace/engines/v1/core/zobrist.dart';

/// Adapter that lets the frozen v1 engine take part in matches through the [ChessEngine] interface.
///
/// Nothing in v1's search or evaluation is changed. Everything here only translates between the shared
/// FEN/UCI strings and v1's own Board/Move types, and reads back information v1 already exposes.
class V1Engine extends ChessEngine {
  static bool _zobristInitialised = false; // Statics are per isolate, so each worker initialises its own keys

  static final RegExp _completedDepthLine = RegExp(r"After searching with depth (\d+)");
  static const int _mateThreshold = 999999000; // v1 scores mate as 999999999 minus the ply count
  static const int _maxPvLength = 10;

  final bool verbose;
  final Engine _engine = Engine();

  V1Engine({this.verbose = false}) {
    if (!_zobristInitialised) {
      Zobrist(); // v1 hashes are all zero until this has run once
      _zobristInitialised = true;
    }
  }

  @override
  String get id => "v1";

  @override
  String get name => "ACE v1";

  @override
  Future<SearchResult> search(EnginePosition position, SearchLimits limits) async {
    Board board = Board.fromFen(position.startFen);
    for (String uci in position.uciMoves) {
      board.makeMove(moveFromUci(board, uci));
    }

    // v1 prints its progress. Swallow those prints and read the completed depth from them.
    int? completedDepth;
    Stopwatch stopwatch = Stopwatch()..start();
    Move? bestMove = await runZoned(
      () => _engine.getBestMove(board, limits.moveTimeMs),
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
        Match? match = _completedDepthLine.firstMatch(line);
        if (match != null) completedDepth = int.parse(match.group(1)!);
        if (verbose) parent.print(zone, line);
      }),
    );
    stopwatch.stop();

    int nodes = _engine.debugInfo.numNodes + _engine.debugInfo.numQNodes;
    if (bestMove == null) {
      return SearchResult(bestMove: null, depth: completedDepth, nodes: nodes, timeMs: stopwatch.elapsedMilliseconds);
    }

    int eval = _engine.bestEval;
    int? mateIn;
    if (eval.abs() > _mateThreshold) {
      int pliesToMate = 999999999 - eval.abs();
      mateIn = eval > 0 ? (pliesToMate + 1) ~/ 2 : -((pliesToMate + 1) ~/ 2);
    }

    return SearchResult(
      bestMove: uciFromMove(bestMove),
      scoreCp: mateIn == null ? eval : null,
      mateIn: mateIn,
      depth: completedDepth,
      nodes: nodes,
      pv: _principalVariation(board, bestMove),
      timeMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Rebuilds the line v1 expects by following the best moves stored in its transposition table
  List<String> _principalVariation(Board board, Move bestMove) {
    MoveGenerator moveGenerator = MoveGenerator();
    List<Move> played = [];
    Set<int> seenPositions = {board.zobristKey};
    Move? next = bestMove;

    while (next != null && played.length < _maxPvLength) {
      board.makeMove(next);
      played.add(next);
      if (!seenPositions.add(board.zobristKey)) break;

      TranspositionTableEntry? entry =
          _engine.transpositionTable.retrieve(board.zobristKey, 0, -2000000000, 2000000000, 0);
      next = null;
      if (entry != null) {
        // Only follow the stored move if it is legal here (guards against hash collisions)
        for (Move legal in moveGenerator.generateLegalMoves(board)) {
          if (legal.isSameAs(entry.bestMove)) next = legal;
        }
      }
    }

    for (Move move in played.reversed) {
      board.unMakeMove(move);
    }
    return played.map(uciFromMove).toList();
  }

  static String uciFromMove(Move move) {
    return UciMove(move.startingSquare, move.targetSquare, move.promotion == 0 ? null : " qnrb"[move.promotion])
        .toString();
  }

  /// Converts a UCI string into a v1 Move, working out the special move flags from the board.
  /// This doesn't rely on v1's move generator, so v1 can always follow any legal move its opponent plays.
  static Move moveFromUci(Board board, String uci) {
    UciMove parsed = UciMove.parse(uci);
    int piece = board.position[parsed.from];
    int pieceType = Piece.type(piece);
    int fileDistance = (parsed.to % 8 - parsed.from % 8).abs();

    return Move(
      startingSquare: parsed.from,
      targetSquare: parsed.to,
      castling: pieceType == Piece.king && fileDistance == 2,
      enPassantCapture: pieceType == Piece.pawn &&
          fileDistance == 1 &&
          board.position[parsed.to] == Piece.none &&
          parsed.to == board.enPassantSquare,
      pawnTwoForward: pieceType == Piece.pawn && (parsed.to - parsed.from).abs() == 16,
      promotion: parsed.promotionCode,
    );
  }
}
