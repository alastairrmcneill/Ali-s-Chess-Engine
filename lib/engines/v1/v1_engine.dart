import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v1/core/move.dart';
import 'package:ace/engines/v1/core/board.dart';
import 'package:ace/engines/v1/core/move_generator.dart';
import 'package:ace/engines/v1/search/searcher.dart';

class V1Engine implements ChessEngine {
  late Searcher searcher;

  @override
  String get id => 'v1';

  @override
  String get displayName => 'v1 - Plain Negamax';

  @override
  void newGame() {
    searcher = Searcher();
  }

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
        throw StateError('v1 move generator does not consider "$uciMove" a legal move');
      }
      board.makeMove(legalMove);
    }

    final nextMove = limits.depth == null
        ? searcher.getBestMove(board, timeLimit: limits.moveTime)
        : searcher.getBestMove(board, depth: limits.depth!);

    if (nextMove == null) {
      throw Exception('No valid move found');
    }

    return EngineMoveResult(
      uciMove: moveToUci(nextMove),
      evaluation: board.whiteToPlay ? searcher.bestEval : -searcher.bestEval,
      depth: limits.depth,
      nodes: searcher.nodes,
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
