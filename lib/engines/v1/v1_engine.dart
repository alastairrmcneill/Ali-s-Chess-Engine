import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v1/core/move.dart';
import 'package:ace/engines/v1/ai/engine.dart';
import 'package:ace/engines/v1/core/board.dart';
import 'package:ace/engines/v1/core/move_generator.dart';
import 'package:ace/engines/v1/core/zobrist.dart';

class V1Engine implements ChessEngine {
  @override
  String get id => 'v1';

  @override
  String get displayName => 'V1 Engine';

  static bool _zobristReady = false;
  late Engine _engine;

  V1Engine() {
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
        throw StateError('v1 move generator does not consider "$uciMove" a legal move');
      }
      board.makeMove(legalMove);
    }

    final bestMove = _engine.getBestMove(
      board,
      limits.moveTime.inMilliseconds,
      onIteration: onIteration == null ? null : (iteration) => onIteration(_toStats(iteration)),
    );

    if (bestMove == null) {
      throw Exception('No valid move found');
    }

    final completed = _engine.searchLog.where((i) => !i.aborted);
    // The move played comes from the last step that produced one, which may be an aborted step.
    final played = _engine.searchLog.where((i) => i.bestMove != null);

    return EngineMoveResult(
      uciMove: moveToUci(bestMove),
      evaluation: _engine.bestEval,
      depth: completed.isEmpty ? null : completed.last.depth,
      nodes: _engine.debugInfo.numNodes + _engine.debugInfo.numQNodes,
      principalVariation: played.isEmpty ? null : played.last.pv.map(moveToUci).toList(),
    );
  }

  SearchStats _toStats(SearchIteration i) => SearchStats(
        depth: i.depth,
        nodes: i.nodes,
        qNodes: i.qNodes,
        transpositions: i.transpositions,
        maxQDepth: i.maxQDepth,
        evaluations: i.evaluations,
        eval: i.eval,
        bestMove: i.bestMove == null ? null : moveToUci(i.bestMove!),
        pv: i.pv.map(moveToUci).toList(),
        elapsed: Duration(milliseconds: i.elapsedMs),
        aborted: i.aborted,
      );

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
