import 'dart:math';

import 'package:ace/chess_engine/ai/evaluation.dart';
import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';

class Engine {
  Evaluation evaluation = Evaluation();
  MoveGenerator moveGenerator = MoveGenerator();
  late Board board;
  int positionsEvaluated = 0;
  Duration searchDuration = Duration(milliseconds: 0);

  Move getBestMove(Board board) {
    positionsEvaluated = 0;
    DateTime startTime = DateTime.now();
    this.board = board;
    int bestEval = -1000000000;
    Move? bestMove = null;

    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);

    for (Move move in legalMoves) {
      this.board.makeMove(move);
      int moveEval = -1 * _search(3);
      this.board.unMakeMove(move);

      if (moveEval > bestEval) {
        bestMove = move;
        bestEval = moveEval;
      }
    }

    // Debugging
    DateTime endTime = DateTime.now();
    searchDuration = endTime.difference(startTime);
    print("Evaluated $positionsEvaluated in ${searchDuration.inMilliseconds}ms");
    return bestMove!;
  }

  int _search(int depth) {
    if (depth == 0) {
      positionsEvaluated += 1;
      return evaluation.evaluate(board);
    }

    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);

    int bestEval = -1000000000;
    for (Move move in legalMoves) {
      board.makeMove(move);
      int moveEval = -1 * _search(depth - 1);
      board.unMakeMove(move);

      bestEval = max(moveEval, bestEval);
    }
    return bestEval;
  }
}
