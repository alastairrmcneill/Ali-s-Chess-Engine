import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:flutter_test/flutter_test.dart';

class _PerftCase {
  final String name;
  final String fen;
  final List<int> expectedCounts;
  _PerftCase(this.name, this.fen, this.expectedCounts);
}

// Same cases as test/engines/perft_all_versions_test.dart, plus two extra chessprogramming.org
// positions, run directly against chess_core/rules' own board + move generator. Depths are capped
// so the suite runs quickly; a rules bug found here is an engine bug too (see docs/manual_plan.md §11).
final List<_PerftCase> _testCases = [
  _PerftCase(
    "starting position",
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    [20, 400, 8902],
  ),
  _PerftCase(
    "Kiwipete",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    [48, 2039],
  ),
  _PerftCase(
    "Position 3",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    [14, 191, 2812, 43238],
  ),
  _PerftCase(
    "Position 4",
    "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    [6, 264, 9467],
  ),
  _PerftCase(
    "Position 5",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    [44, 1486, 62379],
  ),
  _PerftCase(
    "Position 6",
    "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
    [46, 2079, 89890],
  ),
  _PerftCase(
    "promotions",
    "n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1",
    [24, 496, 9483],
  ),
];

int _perft(Board board, int depth) {
  if (depth <= 0) return 1;

  final List<Move> moves = MoveGenerator().generateLegalMoves(board);
  if (depth == 1) return moves.length;

  int nodes = 0;
  for (final move in moves) {
    board.makeMove(move);
    nodes += _perft(board, depth - 1);
    board.unMakeMove(move);
  }
  return nodes;
}

void main() {
  for (final testCase in _testCases) {
    group(testCase.name, () {
      for (int depth = 1; depth <= testCase.expectedCounts.length; depth++) {
        test('depth $depth', () {
          final board = Board.fromFEN(testCase.fen);
          expect(_perft(board, depth), testCase.expectedCounts[depth - 1]);
        });
      }
    });
  }
}
