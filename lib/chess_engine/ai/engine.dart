import 'dart:async';
import 'dart:math';

import 'package:ace/chess_engine/ai/evaluation.dart';
import 'package:ace/chess_engine/ai/move_ordering.dart';
import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';

class Engine {
  Evaluation evaluation = Evaluation();
  MoveGenerator moveGenerator = MoveGenerator();
  MoveOrdering moveOrdering = MoveOrdering();
  late Board board;
  int totalEvaluations = 0;
  int numNodes = 0;
  int numQNodes = 0;
  int maxQSearchDepth = 0;
  bool abortSearch = false;
  Duration maxDuration = const Duration(milliseconds: 2000);
  Duration searchDuration = Duration(milliseconds: 0);
  int checkmateScore = -999999999;
  late Stopwatch stopwatch;
  late Move? bestMove;

  //TODO: Doesn't seem to be finding checkmate anymore for some reason
  //TODO: Doesn't want to protect pawns for some reason either.
  //TODO: Something to do with the aborting of the search and how you determine the best move

  Future<Move?> getBestMove(Board board) async {
    numNodes = 0;
    numQNodes = 0;
    maxQSearchDepth = 0;
    totalEvaluations = 0;
    stopwatch = Stopwatch()..start();
    abortSearch = false;
    DateTime startTime = DateTime.now();
    this.board = board;
    bestMove = null;

    await runIterativeDeepening();

    // Debugging
    DateTime endTime = DateTime.now();
    searchDuration = endTime.difference(startTime);
    print("""Total Positions:  $totalEvaluations,
         Q Search Positions: $numQNodes,
         Q Search max depth: $maxQSearchDepth ply,
         Time taken: ${searchDuration.inMilliseconds}ms,
         Best move: $bestMove
        """);

    stopwatch.stop();
    return bestMove;
  }

  Future<int> search(int depth, int alpha, int beta, int plyFromRoot) async {
    if (stopwatch.elapsed >= maxDuration) {
      abortSearch = true;
      return 0;
      evaluation.evaluate(board); // Or return a default value not sure if this is a good approach because it means
    }
    if (depth == 0) {
      // int eval = evaluation.evaluate(board);
      int eval = quiescenceSearch(alpha, beta, 0);
      return eval;
    }

    //TODO: include draws

    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);
    legalMoves = moveOrdering.orderMoves(board, legalMoves, Move.invalid());
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
      if (abortSearch) break;
      board.makeMove(move);
      int moveEval = -1 * await search(depth - 1, -beta, -alpha, plyFromRoot + 1);
      board.unMakeMove(move);
      numNodes += 1;
      bestEval = max(moveEval, bestEval);
      alpha = max(alpha, moveEval);
      if (alpha >= beta) {
        break; // Cut-off
      }

      // Periodically yield control
      if (stopwatch.elapsedMilliseconds % 10 == 0) {
        await Future.delayed(Duration.zero);
      }

      if (stopwatch.elapsed >= maxDuration) {
        abortSearch = true;
        return 0;
        // evaluation.evaluate(board); // Or return a default value not sure if this is a good approach because it means
      }
    }
    return bestEval;
  }

  int quiescenceSearch(int alpha, int beta, int depth) {
    if (abortSearch) return alpha;
    maxQSearchDepth = max(maxQSearchDepth, depth);
    int eval = evaluation.evaluate(board);
    totalEvaluations += 1;

    if (eval >= beta) return beta;
    if (eval > alpha) {
      alpha = eval;
    }
    // Generate only moves which are captures. If there are no captures then just skip over and return
    List<Move> moves = moveGenerator.generateLegalMoves(board, includeQuietMoves: false);
    moves = moveOrdering.orderMoves(board, moves, Move.invalid());

    for (Move move in moves) {
      board.makeMove(move);
      int eval = -quiescenceSearch(-beta, -alpha, depth + 1);
      board.unMakeMove(move);
      numQNodes += 1;
      if (eval >= beta) return beta;
      if (eval > alpha) {
        alpha = eval;
      }
    }

    return alpha;
  }

  Future<void> runIterativeDeepening() async {
    int bestEval = -1000000000;
    int alpha = -1000000001; // Best already explored option along the path to the root for the maximizer
    int beta = 1000000001; //Best already explored option along the path to the root for the minimizer

    for (int searchDepth = 1; searchDepth < 100; searchDepth++) {
      print("Starting with search of depth $searchDepth");

      List<Move> legalMoves = moveGenerator.generateLegalMoves(board);
      legalMoves = moveOrdering.orderMoves(board, legalMoves, Move.invalid());

      for (Move move in legalMoves) {
        if (abortSearch) break;
        board.makeMove(move);
        int moveEval = -1 * await search(searchDepth, -beta, -alpha, 0);
        board.unMakeMove(move);

        if (moveEval > bestEval) {
          bestMove = move;
          bestEval = moveEval;
        }

        alpha = max(alpha, moveEval);
        if (alpha >= beta) break;

        if (stopwatch.elapsed >= maxDuration) {
          abortSearch = true;
          break;
        }
      }

      print("Best eval: $bestEval");
      print("Best move: $bestMove");

      if (stopwatch.elapsed >= maxDuration) {
        abortSearch = true;
        break;
      }
    }
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
