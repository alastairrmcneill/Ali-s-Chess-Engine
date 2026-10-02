import 'dart:async';

import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v1/ai/engine.dart';
import 'package:ace/engines/v1/core/board.dart';
import 'package:ace/engines/v1/core/move.dart';
import 'package:ace/engines/v1/core/move_generator.dart';
import 'package:ace/engines/v1/core/zobrist.dart';

class V1Engine implements ChessEngine {
  @override
  String get id => 'v1';

  @override
  String get displayName => 'ACE v1';

  static bool _zobristReady = false;
  late Engine _engine;

  V1Engine() {
    _initZobrist();
    _engine = Engine();
  }

  static void _initZobrist() {
    if (_zobristReady) return;
    Zobrist(); // fills the static random tables for THIS snapshot's library
    _zobristReady = true;
  }

  @override
  Future<void> newGame() async {
    _engine = Engine();
  }

  @override
  Future<EngineMoveResult> getMove(String startingFen, List<String> uciMoves, SearchLimits limits) async {
    final board = _boardAfter(startingFen, uciMoves);

    // The engine prints on every iteration. Swallow it, but read the completed depth from it.
    int? completedDepth;
    final depthPattern = RegExp(r'After searching with depth (\d+)');
    final bestMove = await runZoned(
      () => _engine.getBestMove(board, limits.moveTime.inMilliseconds),
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
        final match = depthPattern.firstMatch(line);
        if (match != null) completedDepth = int.parse(match.group(1)!);
      }),
    );

    // The engine can return null, or Move.invalid from a transposition table hit at the root.
    if (bestMove == null || bestMove.startingSquare < 0) {
      throw StateError('$id returned no move');
    }

    // The engine's eval is from the side to move's point of view (negamax); the interface wants White's.
    final eval = board.whiteToPlay ? _engine.bestEval : -_engine.bestEval;

    return EngineMoveResult(
      uciMove: moveToUci(bestMove),
      evaluation: eval,
      depth: completedDepth,
      nodes: _engine.debugInfo.numNodes + _engine.debugInfo.numQNodes,
    );
  }

  @override
  int perft(String fen, int depth) {
    return _perft(Board.fromFEN(fen), depth);
  }

  int _perft(Board board, int depth) {
    if (depth <= 0) return 1;

    final moves = MoveGenerator().generateLegalMoves(board);
    if (depth == 1) return moves.length;

    int nodes = 0;
    for (final move in moves) {
      board.makeMove(move);
      nodes += _perft(board, depth - 1);
      board.unMakeMove(move);
    }
    return nodes;
  }

  /// Builds this version's board from [fen] and replays [uciMoves], so it sees the repetition history.
  /// Throws [StateError] if this version's own move generator doesn't think a move is legal.
  static Board _boardAfter(String fen, List<String> uciMoves) {
    final board = Board.fromFEN(fen);
    final moveGenerator = MoveGenerator();

    for (int i = 0; i < uciMoves.length; i++) {
      final uciMove = uciMoves[i];
      Move? legalMove;
      for (final candidate in moveGenerator.generateLegalMoves(board)) {
        if (moveToUci(candidate) == uciMove) {
          legalMove = candidate;
          break;
        }
      }
      if (legalMove == null) {
        throw StateError('Engine move generator does not consider "$uciMove" legal (ply ${i + 1})');
      }
      board.makeMove(legalMove);
    }
    return board;
  }

  /// Version-specific mapping from this version's Move to a UCI string. Promotion codes: 1 = q, 2 = n, 3 = r, 4 = b.
  static String moveToUci(Move move) {
    return UciMove(
      from: move.startingSquare,
      to: move.targetSquare,
      promotion: move.promotion == 0 ? null : ' qnrb'[move.promotion],
    ).toString();
  }

  /// Legal moves from this version's own move generator, as UCI. Used by tests.
  static Set<String> legalUciMoves(String fen, List<String> uciMoves) {
    final board = _boardAfter(fen, uciMoves);
    return MoveGenerator().generateLegalMoves(board).map(moveToUci).toSet();
  }
}
