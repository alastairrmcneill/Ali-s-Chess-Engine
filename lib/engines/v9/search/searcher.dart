import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v9/core/board.dart';
import 'package:ace/engines/v9/core/move.dart';
import 'package:ace/engines/v9/core/move_generator.dart';
import 'package:ace/engines/v9/search/evaluator.dart';
import 'package:ace/engines/v9/search/move_ordering.dart';
import 'package:ace/engines/v9/search/transposition_table.dart';

class Searcher {
  late Board board;
  final MoveGenerator moveGenerator = MoveGenerator();
  final MoveOrdering moveOrdering = MoveOrdering();
  final TranspositionTable tt = TranspositionTable();
  final Evaluator evaluator = Evaluator();
  final int mateScore = -999999999;

  static const int drawScore = 40;

  int qCheckDepthLimit = 1;

  int bestEval = -999999999;
  Move? bestMove;
  SearchStats stats = SearchStats();
  bool aborted = false;

  final Stopwatch _stopwatch = Stopwatch();
  Duration? _timeLimit;

  Move? getBestMove(
    Board board, {
    int? depth,
    Duration? timeLimit,
    SearchProgressCallback? onSearchProgressUpdate,
  }) {
    this.board = board;
    stats = SearchStats();
    aborted = false;
    _timeLimit = timeLimit;
    _stopwatch
      ..reset()
      ..start();

    int maxDepth = depth ?? 256;
    bestEval = -999999999;
    bestMove = null;

    final legalMoves = moveGenerator.generateLegalMoves(board);
    List<Move> orderedMoves = moveOrdering.orderMoves(board, legalMoves);

    for (int iterationDepth = 1; iterationDepth <= maxDepth; iterationDepth++) {
      int alpha = -1000000000;
      int beta = 1000000000;
      int iterationEval = -1000000000;
      Move? iterationBestMove;

      for (final move in orderedMoves) {
        board.makeMove(move);
        final eval = -search(iterationDepth - 1, 1, -beta, -alpha);
        board.unMakeMove(move);

        if (aborted) break;

        if (eval > iterationEval) {
          iterationEval = eval;
          iterationBestMove = move;
          alpha = iterationEval;
        }
      }

      if (iterationBestMove != null) {
        bestMove = iterationBestMove;
        bestEval = iterationEval;
        if (!aborted) {
          stats.depth = iterationDepth;
          orderedMoves = [iterationBestMove, ...orderedMoves.where((m) => m != iterationBestMove)];
        }
      }

      _fillStats();
      if (!aborted) onSearchProgressUpdate?.call(stats);

      if (aborted) break;
      if (bestEval.abs() > (mateScore.abs() - 1000)) break;
    }

    bestMove ??= orderedMoves.isNotEmpty ? orderedMoves[0] : null;
    _fillStats();
    return bestMove;
  }

  void _fillStats() {
    stats
      ..eval = bestEval
      ..bestMove = bestMove?.uci ?? ''
      ..pv = bestMove == null ? const [] : [bestMove!.uci]
      ..elapsed = _stopwatch.elapsed
      ..aborted = aborted;
  }

  int search(int depth, int plyFromRoot, int alpha, int beta) {
    stats.nodes++;
    if (_timeLimit != null && (stats.nodes & 1023) == 0 && _stopwatch.elapsed >= _timeLimit!) {
      aborted = true;
    }
    if (aborted) return 0;

    if (plyFromRoot > 0 && (board.hashHistory[board.zobristKey] ?? 0) >= 2) {
      return drawScore; // Threefold repetition
    }

    if (depth == 0) {
      int eval = quiescenceSearch(alpha, beta, plyFromRoot, 0);
      return eval;
    }

    // Probe the transposition table
    final originalAlpha = alpha;
    int ttMove = 0;
    final slot = tt.probe(board.zobristKey);

    if (slot != null) {
      ttMove = tt.moveAt(slot);
      if (tt.depthAt(slot) >= depth) {
        // Use the transposition table entry

        final score = fromTT(tt.scoreAt(slot), plyFromRoot);
        final flag = tt.flagAt(slot);
        if (flag == TranspositionTable.exact) {
          stats.transpositions++;
          return score;
        }
        if (flag == TranspositionTable.lower && score >= beta) {
          stats.transpositions++;
          return beta;
        }
        if (flag == TranspositionTable.upper && score <= alpha) {
          stats.transpositions++;
          return alpha;
        }
      }
    }

    final legalMoves = moveGenerator.generateLegalMoves(board);

    if (legalMoves.isEmpty) {
      // either return checkmate or stalemate
      return moveGenerator.inCheck ? mateScore + plyFromRoot : 0;
    }

    // Checked after mate/stalemate, since a mate on the 100th half move still wins.
    if (board.fiftyMoveRule >= 100) return drawScore; // Fifty-move rule draw

    final orderedMoves = moveOrdering.orderMoves(board, legalMoves, ttMove: ttMove);
    Move? bestMoveHere;
    for (int i = 0; i < orderedMoves.length; i++) {
      board.makeMove(orderedMoves[i]);
      final eval = -search(depth - 1, plyFromRoot + 1, -beta, -alpha);
      board.unMakeMove(orderedMoves[i]);

      if (aborted) return 0;

      if (eval >= beta) {
        // Move is too good, prune the rest of the branch
        stats.betaCutoffs++;
        if (i == 0) stats.firstMoveCutoffs++;
        tt.store(board.zobristKey, toTT(beta, plyFromRoot), orderedMoves[i], depth, TranspositionTable.lower);
        return beta;
      }

      if (eval > alpha) {
        alpha = eval;
        bestMoveHere = orderedMoves[i];
      }
    }
    final flag = alpha > originalAlpha ? TranspositionTable.exact : TranspositionTable.upper;
    tt.store(board.zobristKey, toTT(alpha, plyFromRoot), bestMoveHere ?? Move.invalid, depth, flag);
    return alpha;
  }

  int quiescenceSearch(int alpha, int beta, int plyFromRoot, int qDepth) {
    stats.nodes++;
    stats.qNodes++;
    if (qDepth > stats.maxQDepth) stats.maxQDepth = qDepth;
    if (_timeLimit != null && (stats.nodes & 1023) == 0 && _stopwatch.elapsed >= _timeLimit!) {
      aborted = true;
    }
    if (aborted) return 0;

    List<Move> moves = [];
    final inCheck = moveGenerator.isInCheck(board);
    if (inCheck) stats.qCheckNodes++;

    if (inCheck && qDepth < qCheckDepthLimit) {
      // Can't stand pat in check, every legal reply has to be considered.
      moves = moveGenerator.generateLegalMoves(board);
      if (moves.isEmpty) return mateScore + plyFromRoot;
    } else {
      // Too deep to search every evasion, but still notice checkmate.
      if (inCheck && moveGenerator.generateLegalMoves(board).isEmpty) return mateScore + plyFromRoot;

      stats.evaluations++;
      final standPat = evaluator.evaluate(board);
      if (standPat >= beta) {
        stats.qBetaCutoffs++;
        return beta;
      }
      alpha = standPat > alpha ? standPat : alpha;
      moves = moveGenerator.generateLegalMoves(board, includeQuietMoves: false);
    }

    final orderedMoves = moveOrdering.orderMoves(board, moves);

    for (final move in orderedMoves) {
      board.makeMove(move);
      final eval = -quiescenceSearch(-beta, -alpha, plyFromRoot + 1, qDepth + 1);
      board.unMakeMove(move);

      if (aborted) return 0;

      if (eval >= beta) {
        stats.qBetaCutoffs++;
        return beta;
      }

      alpha = eval > alpha ? eval : alpha;
    }

    return alpha;
  }

  bool isMate(int score) => score.abs() > (mateScore.abs() - 1000);
  int toTT(int score, int ply) => !isMate(score) ? score : (score > 0 ? score + ply : score - ply);
  int fromTT(int score, int ply) => !isMate(score) ? score : (score > 0 ? score - ply : score + ply);
}
