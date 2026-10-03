import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v3/core/move.dart';
import 'package:ace/engines/v3/ai/engine.dart';
import 'package:ace/engines/v3/core/board.dart';
import 'package:ace/engines/v3/core/move_generator.dart';
import 'package:ace/engines/v3/core/zobrist.dart';

class V3Engine implements ChessEngine {
  @override
  String get id => 'v3';

  @override
  String get displayName => 'V3 Engine (negamax)';

  static bool _zobristReady = false;
  late Engine _engine;

  V3Engine() {
    _initZobrist();
    _engine = Engine();
  }

  static void _initZobrist() {
    if (_zobristReady) return;
    Zobrist(); // fills the static random tables for THIS snapshot's library
    _zobristReady = true;
  }

  @override
  void newGame() {
    _engine = Engine();
  }

  @override
  EngineMoveResult getMove(
    String startingFen,
    List<String> uciMoves,
    SearchLimits limits, {
    SearchProgressCallback? onIteration,
  }) {
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
        throw StateError('v3 move generator does not consider "$uciMove" a legal move');
      }
      board.makeMove(legalMove);
    }

    final stopwatch = Stopwatch()..start();
    final bestMove = _engine.getBestMove(board);

    if (bestMove == null) {
      throw Exception('No valid move found');
    }

    // No iterative deepening, so the single "iteration" is the whole search. This is what the app shows.
    onIteration?.call(SearchStats(
      depth: _engine.depth,
      nodes: _engine.nodes,
      qNodes: 0,
      transpositions: 0,
      maxQDepth: 0,
      evaluations: _engine.evaluations,
      eval: _engine.bestEval,
      bestMove: moveToUci(bestMove),
      pv: _engine.principalVariation.map(moveToUci).toList(),
      elapsed: stopwatch.elapsed,
    ));

    return EngineMoveResult(
      uciMove: moveToUci(bestMove),
      evaluation: _engine.bestEval,
      depth: _engine.depth,
      nodes: _engine.nodes,
      principalVariation: _engine.principalVariation.map(moveToUci).toList(),
    );
  }

  @override
  int perft(String fen, int depth) {
    return _perft(Board.fromFEN(fen), depth);
  }

  int _perft(Board board, int depth) {
    if (depth <= 0) return 1;

    final moves = MoveGenerator().generateLegalMoves(board);
    if (depth == 1) return moves.length;

    int nodes = 0;
    for (final move in moves) {
      board.makeMove(move);
      nodes += _perft(board, depth - 1);
      board.unMakeMove(move);
    }
    return nodes;
  }

  String moveToUci(Move move) {
    return UciMove(
            from: move.startingSquare,
            to: move.targetSquare,
            promotion: move.promotion == 0 ? null : " qnrb"[move.promotion])
        .toString();
  }
}
