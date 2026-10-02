import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:ace/chess_core/rules/zobrist.dart';
import 'package:flutter_test/flutter_test.dart';

int _perft(Board board, int depth) {
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

/// The referee's rules core must be correct: these are the standard perft positions from chessprogramming.org.
final _cases = <String, (String, List<int>)>{
  'start position': ('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', [20, 400, 8902, 197281]),
  'Kiwipete': ('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', [48, 2039, 97862]),
  'position 3': ('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', [14, 191, 2812, 43238, 674624]),
  'position 4': ('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', [6, 264, 9467, 422333]),
  'position 5': ('rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', [44, 1486, 62379]),
  'position 6': ('r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10', [46, 2079, 89890]),
  'promotions': ('n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1', [24, 496, 9483, 182838]),
};

void main() {
  setUpAll(() => Zobrist());

  _cases.forEach((name, testCase) {
    final (fen, expected) = testCase;
    for (int depth = 1; depth <= expected.length; depth++) {
      test('$name depth $depth', () => expect(_perft(Board.fromFEN(fen), depth), expected[depth - 1]));
    }
  });
}
