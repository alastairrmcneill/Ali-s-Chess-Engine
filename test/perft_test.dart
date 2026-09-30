import 'package:ace/chess_engine/core/board.dart';
import 'package:ace/chess_engine/core/move.dart';
import 'package:ace/chess_engine/core/move_generator.dart';
import 'package:flutter_test/flutter_test.dart';

class PerftTestCase {
  final String name;
  final String fen;
  final List<int> expectedCounts;

  PerftTestCase(this.name, this.fen, this.expectedCounts);
}

int performPerft(Board board, int depth) {
  final moveGenerator = MoveGenerator();

  List<Move> moves = moveGenerator.generateLegalMoves(board);
  if (depth == 1) return moves.length;

  int nodes = 0;
  for (Move move in moves) {
    board.makeMove(move);
    nodes += performPerft(board, depth - 1);
    board.unMakeMove(move);
  }
  return nodes;
}

void main() {
  List<PerftTestCase> testCases = [
    PerftTestCase(
      "starting position",
      "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      [
        20,
        400,
        8902,
        197281,
        4865609,
      ],
    ),
    PerftTestCase(
      "Kiwipete",
      "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
      [
        48,
        2039,
        97862,
        4085603,
      ],
    ),
    PerftTestCase(
      "Position 3",
      "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
      [
        14,
        191,
        2812,
        43238,
        674624,
      ],
    ),
    PerftTestCase(
      "Position 4",
      "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
      [
        6,
        264,
        9467,
        422333,
        15833292,
      ],
    ),
    PerftTestCase(
      "Position 5",
      "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
      [
        44,
        1486,
        62379,
        2103487,
        89941194,
      ],
    ),
    PerftTestCase(
      "Position 6",
      "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
      [
        46,
        2079,
        89890,
        3894594,
      ],
    ),
  ];
  group('Perft Tests', () {
    testCases.forEach((testCase) {
      group(testCase.name, () {
        for (int depth = 1; depth <= testCase.expectedCounts.length; depth++) {
          test('depth $depth', () {
            final startTime = DateTime.now();
            final board = Board.fromFEN(testCase.fen);

            final result = performPerft(board, depth);
            final endTime = DateTime.now();
            final duration = endTime.difference(startTime);
            print(
                'Perft test "${testCase.name}" depth $depth took ${duration.inMilliseconds} ms (expected ${testCase.expectedCounts[depth - 1]}, got $result)');
            expect(result, testCase.expectedCounts[depth - 1]);
          });
        }
      });
    });
  });
}
