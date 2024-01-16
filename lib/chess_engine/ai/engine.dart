import 'dart:async';
import 'dart:math';

import 'package:ace/chess_engine/ai/evaluation.dart';
import 'package:ace/chess_engine/ai/move_ordering.dart';
import 'package:ace/chess_engine/ai/transposition_table.dart';
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
  int numTranspositions = 0;
  int maxQSearchDepth = 0;
  bool abortSearch = false;
  Duration maxDuration = const Duration(milliseconds: 2000);
  Duration searchDuration = Duration(milliseconds: 0);
  int checkmateScore = -999999999;
  late Stopwatch stopwatch;
  late Move? bestMove;
  late int bestEval;
  late Move? bestMoveThisIteration;
  late int bestEvalThisIteration;
  bool hasSearchedAtLeastOneMove = false;
  TranspositionTable transpositionTable = TranspositionTable(100000000);

  Future<Move?> getBestMove(Board board, int thinkingTime) async {
    maxDuration = Duration(milliseconds: thinkingTime);
    numNodes = 0;
    numQNodes = 0;
    numTranspositions = 0;
    maxQSearchDepth = 0;
    totalEvaluations = 0;
    transpositionTable.clear();
    stopwatch = Stopwatch()..start();
    abortSearch = false;
    DateTime startTime = DateTime.now();
    this.board = board;
    bestMove = bestMoveThisIteration = null;
    bestEval = bestEvalThisIteration = 0;

    await runIterativeDeepening();

    // Debugging
    DateTime endTime = DateTime.now();
    searchDuration = endTime.difference(startTime);
    print("""Total Positions:  $totalEvaluations,
         Q Search Positions: $numQNodes,
         Q Search max depth: $maxQSearchDepth ply,
         Transpositions: $numTranspositions, 
         Time taken: ${searchDuration.inMilliseconds}ms,
         Best move: $bestMove
        """);

    stopwatch.stop();
    return bestMove;
  }

  Future<void> runIterativeDeepening() async {
    for (int searchDepth = 1; searchDepth <= 200; searchDepth++) {
      print("Starting with search of depth $searchDepth");
      int alpha = -1000000001; // Best already explored option along the path to the root for the maximizer
      int beta = 1000000001; //Best already explored option along the path to the root for the minimizer
      bestEvalThisIteration = -1000000000;
      bestMoveThisIteration = null;
      hasSearchedAtLeastOneMove = false;

      await search(searchDepth, alpha, beta, 0);

      if (abortSearch) {
        if (hasSearchedAtLeastOneMove) {
          bestMove = bestMoveThisIteration;
          bestEval = bestEvalThisIteration;
          print("Search aborted during search $searchDepth: ");
          print("Best eval: $bestEval");
          print("Best move: $bestMove");
        }

        break;
      } else {
        bestMove = bestMoveThisIteration;
        bestEval = bestEvalThisIteration;
        print("After searching with depth $searchDepth: ");
        print("Best eval: $bestEval");
        print("Best move: $bestMove");
      }

      if (stopwatch.elapsed >= maxDuration) {
        abortSearch = true;
        break;
      }
    }
  }

  Future<int> search(int depth, int alpha, int beta, int plyFromRoot) async {
    if (stopwatch.elapsed >= maxDuration) {
      abortSearch = true;
      return 0;
      evaluation.evaluate(board); // Or return a default value not sure if this is a good approach because it means
    }

    TranspositionTableEntry? entry = transpositionTable.retrieve(board.zobristKey, depth, alpha, beta, plyFromRoot);
    if (entry != null) {
      numTranspositions += 1;
      // If this is the first node then set the best move in this iteration otherwise just return the eval
      if (plyFromRoot == 0) {
        bestMoveThisIteration = entry.bestMove;
        bestEvalThisIteration = entry.eval;
      }
      return entry.eval;
    }

    if (depth == 0) {
      // int eval = evaluation.evaluate(board);
      int eval = quiescenceSearch(alpha, beta, 0);
      return eval;
    }

    // Check for draws
    if (board.hashHistory.values.any((element) => element >= 3)) {
      return 0;
    }

    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);
    legalMoves = moveOrdering.orderMoves(board, legalMoves, bestMove ?? Move.invalid());

    // Check game state.
    if (legalMoves.isEmpty) {
      if (moveGenerator.inCheck) {
        // then in checkmate so return a really bad score
        // Add the ply from root to encourage checkmate in less moves
        return checkmateScore + plyFromRoot;
      }
      return 0;
    }

    Move bestMoveInThisPosition = Move.invalid();
    EntryType type = EntryType.upperBound;

    for (Move move in legalMoves) {
      if (abortSearch) break;
      board.makeMove(move);
      int moveEval = -1 * await search(depth - 1, -beta, -alpha, plyFromRoot + 1);
      board.unMakeMove(move);
      numNodes += 1;

      if (stopwatch.elapsed >= maxDuration) {
        abortSearch = true;
        return 0;
        // evaluation.evaluate(board); // Or return a default value not sure if this is a good approach because it means
      }

      // Move is too good. Get rid of the rest.
      if (moveEval >= beta) {
        transpositionTable.addEntry(
          TranspositionTableEntry(
            zobristHash: board.zobristKey,
            depth: depth,
            eval: beta,
            type: EntryType.lowerBound,
            bestMove: move,
          ),
        );
        // break; // TODO - should i return or break here

        return beta; // Cut-off
      }

      // Found a new best move in this position
      if (moveEval > alpha) {
        alpha = moveEval;
        bestMoveInThisPosition = move;
        type = EntryType.exact;
        // If this is our first layer down then store this as the best move this iteration
        if (plyFromRoot == 0) {
          bestEvalThisIteration = moveEval;
          bestMoveThisIteration = move;
          hasSearchedAtLeastOneMove = true;
        }
      }

      // Periodically yield control
      if (stopwatch.elapsedMilliseconds % 10 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // Update Transposition table
    transpositionTable.addEntry(
      TranspositionTableEntry(
        zobristHash: board.zobristKey,
        depth: depth,
        eval: alpha,
        type: type,
        bestMove: bestMoveInThisPosition,
      ),
    );

    return alpha;
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
