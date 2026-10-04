import 'package:ace/engines/v2/core/board.dart';
import 'package:ace/engines/v2/core/move_generator.dart';
import 'package:ace/engines/v2/core/zobrist.dart';
import 'package:ace/engines/v2/search/evaluator.dart';
import 'package:ace/engines/v2/search/searcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference negamax with no pruning. Alpha-beta must return exactly the same score.
int _plain(Board board, MoveGenerator gen, Evaluator eval, int depth, int ply) {
  if (depth == 0) return eval.evaluate(board);
  final moves = gen.generateLegalMoves(board);
  if (moves.isEmpty) return gen.inCheck ? -999999999 + ply : 0;
  var best = -999999999;
  for (final move in moves) {
    board.makeMove(move);
    final score = -_plain(board, gen, eval, depth - 1, ply + 1);
    board.unMakeMove(move);
    if (score > best) best = score;
  }
  return best;
}

void main() {
  setUpAll(() => Zobrist());

  final cases = <String, (String, int)>{
    'start': ('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 4),
    'kiwipete': ('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', 3),
    'position 3': ('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', 4),
    'position 4': ('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', 3),
    'position 5': ('rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', 3),
    'back rank mate': ('6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1', 4),
    'free queen': ('4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1', 4),
    'mate vs stalemate': ('k7/2Q5/1K6/8/8/8/8/8 w - - 0 1', 4),
  };

  cases.forEach((name, data) {
    final (fen, maxDepth) = data;
    for (var depth = 1; depth <= maxDepth; depth++) {
      test('alpha-beta == plain negamax, $name depth $depth', () {
        final plain = _plain(Board.fromFEN(fen), MoveGenerator(), Evaluator(), depth, 0);
        final searcher = Searcher();
        final move = searcher.getBestMove(Board.fromFEN(fen), depth: depth);
        expect(move, isNotNull);
        expect(searcher.bestEval, plain);
      });
    }
  });
}
