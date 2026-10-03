import 'dart:math';

import 'package:ace/engines/v1/ai/evaluation.dart';
import 'package:ace/engines/v1/ai/move_ordering.dart';
import 'package:ace/engines/v1/ai/transposition_table.dart';
import 'package:ace/engines/v1/core/board.dart';
import 'package:ace/engines/v1/core/move.dart';
import 'package:ace/engines/v1/core/move_generator.dart';

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

  /// One entry per iterative deepening step of the latest [getBestMove], in order.
  List<SearchIteration> searchLog = [];
  void Function(SearchIteration iteration)? onIteration;

  Move? getBestMove(Board board, int thinkingTime, {void Function(SearchIteration iteration)? onIteration}) {
    // Reset values
    maxDuration = Duration(milliseconds: thinkingTime);
    debugInfo = DebugInfo();
    searchLog = [];
    this.onIteration = onIteration;
    transpositionTable.clear();
    stopwatch = Stopwatch()..start();
    abortSearch = false;

    this.board = board;
    bestMove = bestMoveThisIteration = null;
    bestEval = bestEvalThisIteration = 0;

    // Run search
    runIterativeDeepening();

    stopwatch.stop();
    return bestMove;
  }

  void runIterativeDeepening() {
    for (int searchDepth = 1; searchDepth <= 200; searchDepth++) {
      int alpha = -1000000001; // Best already explored option along the path to the root for the maximizer
      int beta = 1000000001; //Best already explored option along the path to the root for the minimizer
      bestEvalThisIteration = -1000000000;
      bestMoveThisIteration = null;
      hasSearchedAtLeastOneMove = false;

      search(searchDepth, alpha, beta, 0);

      if (abortSearch) {
        if (hasSearchedAtLeastOneMove) {
          bestMove = bestMoveThisIteration;
          bestEval = bestEvalThisIteration;
        }
        _recordIteration(searchDepth, aborted: true);

        break;
      } else {
        bestMove = bestMoveThisIteration;
        bestEval = bestEvalThisIteration;
        _recordIteration(searchDepth, aborted: false);
      }

      if (stopwatch.elapsed >= maxDuration) {
        abortSearch = true;
        break;
      }
    }
  }

  void _recordIteration(int depth, {required bool aborted}) {
    final move = bestMoveThisIteration;
    final iteration = SearchIteration(
      depth: depth,
      eval: bestEvalThisIteration,
      bestMove: move,
      pv: aborted ? [if (move != null) move] : _principalVariation(move, depth),
      elapsedMs: stopwatch.elapsedMilliseconds,
      aborted: aborted,
      nodes: debugInfo.numNodes,
      qNodes: debugInfo.numQNodes,
      transpositions: debugInfo.numTranspositions,
      maxQDepth: debugInfo.maxQSearchDepth,
      evaluations: debugInfo.totalEvaluations,
    );
    searchLog.add(iteration);
    onIteration?.call(iteration);
  }

  /// Best-effort line starting with [first], extended by following the transposition table's best moves.
  /// Read-only diagnostics: the board is restored and nothing here influences move choice.
  List<Move> _principalVariation(Move? first, int maxLength) {
    if (first == null) return [];
    final line = <Move>[first];
    final seen = <int>{board.zobristKey};
    board.makeMove(first);
    while (line.length < maxLength) {
      if (!seen.add(board.zobristKey)) break;
      final entry = transpositionTable.peek(board.zobristKey);
      if (entry == null) break;
      final next = moveGenerator.generateLegalMoves(board).where((m) =>
          m.startingSquare == entry.bestMove.startingSquare &&
          m.targetSquare == entry.bestMove.targetSquare &&
          m.promotion == entry.bestMove.promotion);
      if (next.isEmpty) break;
      line.add(next.first);
      board.makeMove(next.first);
    }
    for (final move in line.reversed) {
      board.unMakeMove(move);
    }
    return line;
  }

  int search(int depth, int alpha, int beta, int plyFromRoot) {
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
      int moveEval = -1 * search(depth - 1, -beta, -alpha, plyFromRoot + 1);

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

class SearchIteration {
  final int depth;
  final int eval;
  final Move? bestMove;
  final List<Move> pv;
  final int elapsedMs; // stopwatch time when this iteration ended
  final bool aborted; // ran out of time before finishing
  final int nodes;
  final int qNodes;
  final int transpositions;
  final int maxQDepth;
  final int evaluations;

  const SearchIteration({
    required this.depth,
    required this.eval,
    required this.bestMove,
    required this.pv,
    required this.elapsedMs,
    required this.aborted,
    required this.nodes,
    required this.qNodes,
    required this.transpositions,
    required this.maxQDepth,
    required this.evaluations,
  });
}
