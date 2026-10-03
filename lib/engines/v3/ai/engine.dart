import 'package:ace/engines/v3/ai/evaluation.dart';
import 'package:ace/engines/v3/core/board.dart';
import 'package:ace/engines/v3/core/move.dart';
import 'package:ace/engines/v3/core/move_generator.dart';

/// Plain fixed-depth negamax: no alpha-beta, no move ordering, no transposition table, no quiescence search,
/// no iterative deepening and no time control. Every improvement is meant to be added on top of this later.
class Engine {
  static const int mateScore = 1000000;

  final Evaluation evaluation = Evaluation();
  final MoveGenerator moveGenerator = MoveGenerator();
  final int depth;

  late Board board;

  int nodes = 0;
  int evaluations = 0; // positions statically evaluated (leaf nodes)
  Move? bestMove;
  int bestEval = 0;
  List<Move> principalVariation = [];

  Engine({this.depth = 3});

  Move? getBestMove(Board board) {
    this.board = board;
    nodes = 0;
    evaluations = 0;
    bestMove = null;
    bestEval = 0;
    principalVariation = [];

    final pv = <Move>[];
    bestEval = negamax(depth, 0, pv);
    principalVariation = pv;
    bestMove = pv.isEmpty ? null : pv.first;
    return bestMove;
  }

  /// Score of the position for the side to move. [pv] is filled with the best line found from here.
  int negamax(int depth, int plyFromRoot, List<Move> pv) {
    nodes++;

    if (depth == 0) {
      evaluations++;
      return evaluation.evaluate(board);
    }

    final moves = moveGenerator.generateLegalMoves(board);
    if (moves.isEmpty) {
      // Checkmate (prefer the quickest one) or stalemate
      return moveGenerator.inCheck ? -mateScore + plyFromRoot : 0;
    }

    int best = -2 * mateScore;
    for (final move in moves) {
      final childPv = <Move>[];
      board.makeMove(move);
      final eval = -negamax(depth - 1, plyFromRoot + 1, childPv);
      board.unMakeMove(move);

      if (eval > best) {
        best = eval;
        pv
          ..clear()
          ..add(move)
          ..addAll(childPv);
      }
    }
    return best;
  }
}
