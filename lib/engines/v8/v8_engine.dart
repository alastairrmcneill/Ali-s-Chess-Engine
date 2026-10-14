import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v8/core/move.dart';
import 'package:ace/engines/v8/core/board.dart';
import 'package:ace/engines/v8/core/move_generator.dart';
import 'package:ace/engines/v8/core/zobrist.dart';
import 'package:ace/engines/v8/search/opening_book.dart';
import 'package:ace/engines/v8/search/searcher.dart';

class V8Engine implements ChessEngine {
  Searcher? _searcher;

  // Created on first use so getMove works without a prior newGame().
  Searcher get searcher => _searcher ??= Searcher();

  @override
  String get id => 'v8';

  @override
  String get displayName => 'V8 - Transposition Tables';

  @override
  void newGame() {
    Zobrist.ensureInitialised();
    _searcher = Searcher();
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
        throw StateError('v8 move generator does not consider "$uciMove" a legal move');
      }
      board.makeMove(legalMove);
    }

    if (uciMoves.length < 6 && startingFen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") {
      final openingBookMove = OpeningBook().pickMove(uciMoves);
      if (openingBookMove != null) {
        return EngineMoveResult(
          uciMove: openingBookMove,
          evaluation: 0,
          depth: 0,
          nodes: 0,
          principalVariation: [],
          stats: searcher.stats,
        );
      }
    }

    final stopwatch = Stopwatch()..start();
    final nextMove = limits.depth == null
        ? searcher.getBestMove(board, timeLimit: limits.moveTime, onSearchProgressUpdate: onSearchProgressUpdate)
        : searcher.getBestMove(board, depth: limits.depth!, onSearchProgressUpdate: onSearchProgressUpdate);
    stopwatch.stop();

    if (nextMove == null) {
      throw Exception('No valid move found');
    }

    return EngineMoveResult(
      uciMove: moveToUci(nextMove),
      evaluation: board.whiteToPlay ? searcher.bestEval : -searcher.bestEval,
      depth: searcher.stats.depth,
      nodes: searcher.stats.nodes,
      principalVariation: searcher.stats.pv,
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

  String moveToUci(Move move) => move.uci;
}
