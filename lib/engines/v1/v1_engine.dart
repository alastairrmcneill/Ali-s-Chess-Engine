import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v1/core/move.dart';
import 'package:ace/engines/v1/ai/engine.dart';
import 'package:ace/engines/v1/core/board.dart';
import 'package:ace/engines/v1/core/move_generator.dart';
import 'package:ace/engines/v1/core/zobrist.dart';

class V1Engine implements ChessEngine {
  @override
  String get id => 'v1';

  @override
  String get displayName => 'V1 Engine';

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
    final board = Board.fromFEN(startingFen);
    final moveGenerator = MoveGenerator();

    for (final uciMove in uciMoves) {
      Move? legalMove;
      for (final candidate in moveGenerator.generateLegalMoves(board)) {
        if (moveToUci(candidate) == uciMove) {
          legalMove = candidate;
          break;
        }
      }
      if (legalMove == null) {
        throw StateError('v1 move generator does not consider "$uciMove" a legal move');
      }
      board.makeMove(legalMove);
    }

    final bestMove = await _engine.getBestMove(board, limits.moveTime.inMilliseconds);

    if (bestMove == null) {
      throw Exception('No valid move found');
    }

    return EngineMoveResult(
      uciMove: moveToUci(bestMove),
      evaluation: _engine.bestEval,
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

  String moveToUci(Move move) {
    return UciMove(
            from: move.startingSquare,
            to: move.targetSquare,
            promotion: move.promotion == 0 ? null : " qnrb"[move.promotion])
        .toString();
  }
}
