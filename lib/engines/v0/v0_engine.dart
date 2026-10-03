import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v0/core/move.dart';
import 'package:ace/engines/v0/core/board.dart';
import 'package:ace/engines/v0/core/move_generator.dart';

class V0Engine implements ChessEngine {
  @override
  String get id => 'v0';

  @override
  String get displayName => 'v0 Engine';

  @override
  void newGame() {}

  @override
  EngineMoveResult getMove(
    String startingFen,
    List<String> uciMoves,
    SearchLimits limits, {
    SearchProgressCallback? onIteration,
  }) {
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

    final legalMoves = moveGenerator.generateLegalMoves(board);

    legalMoves.shuffle();

    return EngineMoveResult(
      uciMove: moveToUci(legalMoves.first),
      evaluation: 0,
      nodes: 0,
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
