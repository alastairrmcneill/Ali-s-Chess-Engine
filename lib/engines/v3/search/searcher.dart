import 'package:ace/engines/v3/core/board.dart';
import 'package:ace/engines/v3/core/move.dart';
import 'package:ace/engines/v3/core/move_generator.dart';
import 'package:ace/engines/v3/search/evaluator.dart';
import 'package:ace/engines/v3/search/move_ordering.dart';

class Searcher {
  late Board board;
  final MoveGenerator moveGenerator = MoveGenerator();
  final MoveOrdering moveOrdering = MoveOrdering();
  final Evaluator evaluator = Evaluator();

  int bestEval = -999999999;
  Move? bestMove;
  int nodes = 0;
  bool aborted = false;

  final Stopwatch _stopwatch = Stopwatch();
  Duration? _timeLimit;

  /// Fixed depth negamax. With [timeLimit] the search stops once time is up and returns the best
  /// move among the root moves that were fully searched.
  Move? getBestMove(Board board, {int depth = 4, Duration? timeLimit}) {
    this.board = board;
    int alpha = -1000000000;
    int beta = 1000000000;
    bestEval = -999999999;
    bestMove = null;
    nodes = 0;
    aborted = false;
    _timeLimit = timeLimit;
    _stopwatch
      ..reset()
      ..start();

    final legalMoves = moveGenerator.generateLegalMoves(board);
    final orderedMoves = moveOrdering.orderMoves(board, legalMoves);

    for (final move in orderedMoves) {
      board.makeMove(move);
      final eval = -search(depth - 1, 1, -beta, -alpha);
      board.unMakeMove(move);

      // A move cut short by the clock has an unreliable score, so it never counts.
      if (aborted && bestMove != null) break;

      if (eval > bestEval) {
        bestEval = eval;
        bestMove = move;
        alpha = bestEval;
      }
    }

    return bestMove;
  }

  int search(int depth, int plyFromRoot, int alpha, int beta) {
    nodes++;
    if (_timeLimit != null && (nodes & 1023) == 0 && _stopwatch.elapsed >= _timeLimit!) {
      aborted = true;
    }
    if (aborted) return 0;

    if (plyFromRoot > 0 && (board.hashHistory[board.zobristKey] ?? 0) >= 2) {
      return 0;
    }

    if (depth == 0) {
      return evaluator.evaluate(board);
    }

    final legalMoves = moveGenerator.generateLegalMoves(board);
    final orderedMoves = moveOrdering.orderMoves(board, legalMoves);

    if (legalMoves.isEmpty) {
      // either return checkmate or stalemate
      return moveGenerator.inCheck ? -999999999 + plyFromRoot : 0;
    }

    // Checked after mate/stalemate, since a mate on the 100th half move still wins.
    if (board.fiftyMoveRule >= 100) return 0;

    for (final move in orderedMoves) {
      board.makeMove(move);
      final eval = -search(depth - 1, plyFromRoot + 1, -beta, -alpha);
      board.unMakeMove(move);

      if (aborted) return 0;

      if (eval >= beta) return beta; // Move is too good, prune the rest of the branch

      alpha = eval > alpha ? eval : alpha;
    }
    return alpha;
  }
}
