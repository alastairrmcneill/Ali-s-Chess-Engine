import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v2/core/move.dart';
import 'package:ace/engines/v2/core/board.dart';
import 'package:ace/engines/v2/core/move_generator.dart';
import 'package:ace/engines/v2/core/zobrist.dart';
import 'package:ace/engines/v2/search/searcher.dart';

class V2Engine implements ChessEngine {
  late Searcher searcher;

  @override
  String get id => 'v2';

  @override
  String get displayName => 'V2 - Alpha Beta Pruning';

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
        throw StateError('v2 move generator does not consider "$uciMove" a legal move');
      }
      board.makeMove(legalMove);
    }

    final nextMove = searcher.getBestMove(board, timeLimit: limits.moveTime);

    if (nextMove == null) {
      throw Exception('No valid move found');
    }

    return EngineMoveResult(
      uciMove: moveToUci(nextMove),
      evaluation: board.whiteToPlay ? searcher.bestEval : -searcher.bestEval,
      nodes: searcher.nodes,
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
