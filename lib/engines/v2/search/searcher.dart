import 'package:ace/engines/v2/core/board.dart';
import 'package:ace/engines/v2/core/move.dart';
import 'package:ace/engines/v2/core/move_generator.dart';
import 'package:ace/engines/v2/search/evaluator.dart';

class Searcher {
  late Board board;
  final MoveGenerator moveGenerator = MoveGenerator();
  final Evaluator evaluator = Evaluator();

  int bestEval = -999999999;
  Move? bestMove;
  int nodes = 0;
  bool aborted = false;

  final Stopwatch _stopwatch = Stopwatch();
  Duration? _timeLimit;

  /// Fixed depth negamax. With [timeLimit] the search stops once time is up and returns the best
  /// move among the root moves that were fully searched.
  Move? getBestMove(Board board, {int depth = 3, Duration? timeLimit}) {
    this.board = board;
    bestEval = -999999999;
    bestMove = null;
    nodes = 0;
    aborted = false;
    _timeLimit = timeLimit;
    _stopwatch
      ..reset()
      ..start();

    final legalMoves = moveGenerator.generateLegalMoves(board);

    for (final move in legalMoves) {
      board.makeMove(move);
      final eval = -search(depth - 1, 1);
      board.unMakeMove(move);

      // A move cut short by the clock has an unreliable score, so it never counts.
      if (aborted && bestMove != null) break;

      if (eval > bestEval) {
        bestEval = eval;
        bestMove = move;
      }
    }

    return bestMove;
  }

  int search(int depth, int plyFromRoot) {
    nodes++;
    if (_timeLimit != null && (nodes & 1023) == 0 && _stopwatch.elapsed >= _timeLimit!) {
      aborted = true;
    }
    if (aborted) return 0;
    if (depth == 0) {
      return evaluator.evaluate(board);
    }

    final legalMoves = moveGenerator.generateLegalMoves(board);

    if (legalMoves.isEmpty) {
      // either return checkmate or stalemate
      return moveGenerator.inCheck ? -999999999 + plyFromRoot : 0;
    }

    int bestEval = -999999999;

    for (final move in legalMoves) {
      board.makeMove(move);
      final eval = -search(depth - 1, plyFromRoot + 1);
      board.unMakeMove(move);

      if (aborted) return 0;
      if (eval > bestEval) {
        bestEval = eval;
      }
    }
    return bestEval;
  }
}
