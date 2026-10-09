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
    SearchProgressCallback? onSearchProgressUpdate,
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
        throw StateError('v0 move generator does not consider "$uciMove" a legal move');
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
  PerftTestResult perft(String fen, int depth) {
    return _perft(Board.fromFEN(fen), depth);
  }

  PerftTestResult _perft(Board board, int depth) {
    if (depth <= 0) return PerftTestResult(1);

    final moves = MoveGenerator().generateLegalMoves(board);
    final loudMoves = MoveGenerator().generateLegalMoves(board, includeQuietMoves: false);
    if (depth == 1) return PerftTestResult(moves.length, captures: loudMoves.length);

    PerftTestResult result = PerftTestResult(0);
    for (final move in moves) {
      board.makeMove(move);
      final childResult = _perft(board, depth - 1);
      result.nodes += childResult.nodes;
      result.captures = (result.captures ?? 0) + (childResult.captures ?? 0);
      board.unMakeMove(move);
    }
    return result;
  }

  String moveToUci(Move move) {
    return UciMove(
            from: move.startingSquare,
            to: move.targetSquare,
            promotion: move.promotion == 0 ? null : " qnrb"[move.promotion])
        .toString();
  }
}
