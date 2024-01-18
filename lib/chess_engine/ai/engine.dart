import 'dart:async';
import 'dart:math';

import 'package:ace/chess_engine/ai/evaluation.dart';
import 'package:ace/chess_engine/ai/move_ordering.dart';
import 'package:ace/chess_engine/ai/transposition_table.dart';
import 'package:ace/chess_engine/core/board.dart';
import 'package:ace/chess_engine/core/move.dart';
import 'package:ace/chess_engine/core/move_generator.dart';

class Engine {
  Evaluation evaluation = Evaluation();
  MoveGenerator moveGenerator = MoveGenerator();
  MoveOrdering moveOrdering = MoveOrdering();
  TranspositionTable transpositionTable = TranspositionTable();
  DebugInfo debugInfo = DebugInfo();
  late Stopwatch stopwatch;
  late Board board;

  Duration maxDuration = const Duration(milliseconds: 2000);
  bool abortSearch = false;
  int checkmateScore = -999999999;

  late Move? bestMove;
  late int bestEval;
  late Move? bestMoveThisIteration;
  late int bestEvalThisIteration;
  bool hasSearchedAtLeastOneMove = false;

  Future<Move?> getBestMove(Board board, int thinkingTime) async {
    // Reset values
    maxDuration = Duration(milliseconds: thinkingTime);
    debugInfo = DebugInfo();
    transpositionTable.clear();
    stopwatch = Stopwatch()..start();
    abortSearch = false;

    this.board = board;
    bestMove = bestMoveThisIteration = null;
    bestEval = bestEvalThisIteration = 0;

    // Run search
    await runIterativeDeepening();

    // Debugging
    print("""Total Positions:  ${debugInfo.totalEvaluations},
         Q Search Positions: ${debugInfo.numQNodes},
         Q Search max depth: ${debugInfo.maxQSearchDepth} ply,
         Transpositions: ${debugInfo.numTranspositions},
         Best move: $bestMove
        """);

    stopwatch.stop();
    return bestMove;
  }

  Future<void> runIterativeDeepening() async {
    // Async to allow timer to interupt it

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
    // If the thinking time has elapsed
    if (stopwatch.elapsed >= maxDuration) {
      abortSearch = true;
      evaluation.evaluate(board); // Or return a default value not sure if this is a good approach because it means
    }

    // Check if position is already saved and the depth is appropriate
    TranspositionTableEntry? entry = transpositionTable.retrieve(board.zobristKey, depth, alpha, beta, plyFromRoot);
    if (entry != null) {
      debugInfo.numTranspositions += 1;
      // If this is the first node then set the best move in this iteration otherwise just return the eval
      if (plyFromRoot == 0) {
        bestMoveThisIteration = entry.bestMove;
        bestEvalThisIteration = entry.eval;
      }
      return entry.eval;
    }

    // If we have reached the bottom of our search then start a quiesence search
    if (depth == 0) {
      int eval = quiescenceSearch(alpha, beta, 0);
      return eval;
    }

    // Check for draws
    if (board.hashHistory.values.any((element) => element >= 3) || board.fiftyMoveRule > 100) {
      return 0;
    }

    // Generate all possible moves in this position and order them to start with the best
    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);
    legalMoves = moveOrdering.orderMoves(board, legalMoves, bestMove ?? Move.invalid);

    // Check game state for stalemate and checkmate
    if (legalMoves.isEmpty) {
      if (moveGenerator.inCheck) {
        // then in checkmate so return a really bad score
        // Add the ply from root to encourage checkmate in less moves
        return checkmateScore + plyFromRoot;
      }
      return 0;
    }

    // Haven't found the best move in this position yet.
    Move bestMoveInThisPosition = Move.invalid;
    EntryType type = EntryType.upperBound;

    // Loop through all valid moves
    for (Move move in legalMoves) {
      if (abortSearch) break;

      // Play that move
      board.makeMove(move);

      // Search all moves from there
      int moveEval = -1 * await search(depth - 1, -beta, -alpha, plyFromRoot + 1);

      // Un do the move we made above
      board.unMakeMove(move);
      debugInfo.numNodes += 1;

      // If the thinking time has elapsed
      if (stopwatch.elapsed >= maxDuration) {
        abortSearch = true;
        evaluation.evaluate(board); // Or return a default value not sure if this is a good approach because it means
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

      // Periodically yield control so that processes can check the timer
      if (stopwatch.elapsedMilliseconds % 10 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // Update Transposition table with this current position and result of search
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
    // At the end of the search we will continue searching if there are captures to be made
    // Only searching those captures

    // If the thinking time has elapsed
    if (abortSearch) return alpha;

    debugInfo.maxQSearchDepth = max(debugInfo.maxQSearchDepth, depth);
    int eval = evaluation.evaluate(board);
    debugInfo.totalEvaluations += 1;

    // if the eval is too good and we'd never go here then return
    if (eval >= beta) return beta;
    if (eval > alpha) {
      alpha = eval;
    }

    // Generate only moves which are captures. If there are no captures then just skip over and return
    List<Move> moves = moveGenerator.generateLegalMoves(board, includeQuietMoves: false);
    moves = moveOrdering.orderMoves(board, moves, Move.invalid);

    // Loop through moves
    for (Move move in moves) {
      // Play move
      board.makeMove(move);

      // Carry out another Quiescenesearch
      int eval = -quiescenceSearch(-beta, -alpha, depth + 1);

      // Undo the move
      board.unMakeMove(move);
      debugInfo.numQNodes += 1;

      // Check for cut-offs
      if (eval >= beta) return beta;
      if (eval > alpha) {
        alpha = eval;
      }
    }

    return alpha;
  }
}

class DebugInfo {
  int totalEvaluations = 0;
  int numNodes = 0;
  int numQNodes = 0;
  int numTranspositions = 0;
  int maxQSearchDepth = 0;
}
