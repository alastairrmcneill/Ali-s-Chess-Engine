import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v4/core/move.dart';
import 'package:ace/engines/v4/core/board.dart';
import 'package:ace/engines/v4/core/move_generator.dart';
import 'package:ace/engines/v4/core/zobrist.dart';
import 'package:ace/engines/v4/search/searcher.dart';

class V4Engine implements ChessEngine {
  late Searcher searcher;

  @override
  String get id => 'v4';

  @override
  String get displayName => 'V4 - Quiescence';

  @override
  void newGame() {
    Zobrist.ensureInitialised();
    searcher = Searcher();
  }

  @override
  EngineMoveResult getMove(
    String startingFen,
    List<String> uciMoves,
    SearchLimits limits, {
    SearchProgressCallback? onSearchProgressUpdate,
  }) {
    Zobrist.ensureInitialised();
    final board = Board.fromFEN(startingFen);
    final moveGenerator = MoveGenerator();

    for (final uciMove in uciMoves) {
      Move? legalMove;
      for (final candidate in moveGenerator.generateLegalMoves(board)) {
        if (moveToUci(candidate) == uciMove) {
          legalMove = candidate;
          break;
        }
      }
      if (legalMove == null) {
        throw StateError('v4 move generator does not consider "$uciMove" a legal move');
      }
      board.makeMove(legalMove);
    }

    final stopwatch = Stopwatch()..start();
    final nextMove = limits.depth == null
        ? searcher.getBestMove(board, timeLimit: limits.moveTime)
        : searcher.getBestMove(board, depth: limits.depth!);
    stopwatch.stop();

    if (nextMove == null) {
      throw Exception('No valid move found');
    }

    // There is no iterative deepening yet, so the whole search is reported as a single step.
    searcher.stats
      ..depth = limits.depth
      ..eval = searcher.bestEval
      ..bestMove = moveToUci(nextMove)
      ..elapsed = stopwatch.elapsed
      ..aborted = searcher.aborted;
    onSearchProgressUpdate?.call(searcher.stats);

    return EngineMoveResult(
      uciMove: moveToUci(nextMove),
      evaluation: board.whiteToPlay ? searcher.bestEval : -searcher.bestEval,
      depth: limits.depth,
      nodes: searcher.stats.nodes,
      stats: searcher.stats,
    );
  }

  @override
  PerftTestResult perft(String fen, int depth) {
    return _perft(Board.fromFEN(fen), depth, MoveGenerator());
  }

  // One generator is shared down the tree. Building one is expensive and each call returns a fresh move list.
  PerftTestResult _perft(Board board, int depth, MoveGenerator moveGenerator) {
    if (depth <= 0) return PerftTestResult(1);

    final moves = moveGenerator.generateLegalMoves(board);

    // Checked at every node: the cheap check test must agree with the generator's own check flag.
    final isInCheck = moveGenerator.isInCheck(board);
    if (isInCheck != moveGenerator.inCheck) {
      throw StateError(
          'Inconsistent check status: isInCheck=$isInCheck, moveGenerator.inCheck=${moveGenerator.inCheck}');
    }

    final loudMoves = moveGenerator.generateLegalMoves(board, includeQuietMoves: false);
    if (depth == 1) return PerftTestResult(moves.length, captures: loudMoves.length);

    PerftTestResult result = PerftTestResult(0);
    for (final move in moves) {
      board.makeMove(move);
      final childResult = _perft(board, depth - 1, moveGenerator);
      result.nodes += childResult.nodes;
      result.captures = (result.captures ?? 0) + (childResult.captures ?? 0);
      board.unMakeMove(move);
    }
    return result;
  }

  String moveToUci(Move move) {
    return UciMove(
            from: move.startingSquare,
            to: move.targetSquare,
            promotion: move.promotion == 0 ? null : " qnrb"[move.promotion])
        .toString();
  }
}
