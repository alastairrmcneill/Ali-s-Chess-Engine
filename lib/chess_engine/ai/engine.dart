import 'dart:math';

import 'package:ace/chess_engine/ai/evaluation.dart';
import 'package:ace/chess_engine/ai/move_ordering.dart';
import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/fen_utility.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';

class Engine {
  Evaluation evaluation = Evaluation();
  MoveGenerator moveGenerator = MoveGenerator();
  MoveOrdering moveOrdering = MoveOrdering();
  late Board board;
  int positionsEvaluated = 0;
  Duration searchDuration = Duration(milliseconds: 0);
  int checkmateScore = -999999999;

  Move? getBestMove(Board board) {
    positionsEvaluated = 0;
    DateTime startTime = DateTime.now();
    this.board = board;
    int bestEval = -1000000000;
    int alpha = -1000000001; // Best already explored option along the path to the root for the maximizer
    int beta = 1000000001; //Best already explored option along the path to the root for the minimizer

    Move? bestMove = null; //Move.invalid();

    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);
    legalMoves = moveOrdering.orderMoves(this.board, legalMoves);

    for (Move move in legalMoves) {
      this.board.makeMove(move);
      int moveEval = -search(3, -beta, -alpha, 0);
      this.board.unMakeMove(move);

      if (moveEval > bestEval) {
        bestMove = move;
        bestEval = moveEval;
      }
      alpha = max(alpha, moveEval);
      if (alpha >= beta) break;
    }

    // Debugging
    DateTime endTime = DateTime.now();
    searchDuration = endTime.difference(startTime);
    print("Evaluated $positionsEvaluated in ${searchDuration.inMilliseconds}ms");
    return bestMove;
  }

  int search(int depth, int alpha, int beta, int plyFromRoot) {
    if (depth == 0) {
      // int eval = evaluation.evaluate(board);
      int eval = quiescenceSearch(alpha, beta);
      positionsEvaluated += 1;
      return eval;
    }

    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);
    legalMoves = moveOrdering.orderMoves(board, legalMoves);
    // print("Num moves: ${legalMoves.length}");

    // Check game state.
    if (legalMoves.isEmpty) {
      if (moveGenerator.inCheck) {
        // then in checkmate so return a really bad score
        // Add the ply from root to encourage checkmate in less moves
        return checkmateScore + plyFromRoot;
      }
      return 0;
    }

    int bestEval = -1000000000;
    for (Move move in legalMoves) {
      board.makeMove(move);
      int moveEval = -search(depth - 1, -beta, -alpha, plyFromRoot + 1);
      board.unMakeMove(move);

      bestEval = max(moveEval, bestEval);
      alpha = max(alpha, moveEval);
      if (alpha >= beta) {
        break; // Cut-off
      }
    }
    return bestEval;
  }

  int quiescenceSearch(int alpha, int beta) {
    int eval = evaluation.evaluate(board);
    positionsEvaluated += 1;
    if (eval >= beta) return beta;
    if (eval > alpha) {
      alpha = eval;
    }
    // Generate only moves which are captures. If there are no captures then just skip over and return
    List<Move> moves = moveGenerator.generateLegalMoves(board, includeQuietMoves: false);
    if (moves.isEmpty) {
      print(FENUtility.fenFromBoard(board));
    }
    moves = moveOrdering.orderMoves(board, moves);

    for (Move move in moves) {
      board.makeMove(move);
      int eval = -quiescenceSearch(-beta, -alpha);
      board.unMakeMove(move);
      if (eval >= beta) return beta;
      if (eval > alpha) {
        alpha = eval;
      }
    }

    return alpha;
  }

  bool checkDraw() {
    // Check 50 moves
    if (board.fiftyMoveRule >= 100) {
      return true;
    }

    // Check for 1 repetition
    if (board.positionRepetitionHistory
            .where(
              (element) => element.toString() == board.position.toString(),
            )
            .length ==
        2) {
      return true;
    }

    // Don't need to check insufficient material as the board will avoid losing pieces in the end game anyways

    // If all pass then we are still playing
    return false;
  }
}
