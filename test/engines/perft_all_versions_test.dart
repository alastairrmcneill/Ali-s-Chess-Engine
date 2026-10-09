import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class PerftTestCase {
  final String name;
  final String fen;
  final List<PerftTestResult> expectedCounts;

  PerftTestCase(this.name, this.fen, this.expectedCounts);
}

// Depths are capped relative to test/perft_test.dart's originals so the full suite runs in < 1 min per version.
final List<PerftTestCase> _testCases = [
  PerftTestCase(
    "starting position",
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    [
      PerftTestResult(20, captures: 0),
      PerftTestResult(400, captures: 0),
      PerftTestResult(8902, captures: 34),
      PerftTestResult(197281, captures: 1576),
      PerftTestResult(4865609, captures: 82719),
    ],
  ),
  PerftTestCase(
    "Kiwipete",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    [
      PerftTestResult(48, captures: 8),
      PerftTestResult(2039, captures: 351),
      PerftTestResult(97862, captures: 17102),
      PerftTestResult(4085603, captures: 757163),
    ],
  ),
  PerftTestCase(
    "Position 3",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    [
      PerftTestResult(14, captures: 1),
      PerftTestResult(191, captures: 14),
      PerftTestResult(2812, captures: 209),
      PerftTestResult(43238, captures: 3348),
      PerftTestResult(674624, captures: 52051),
      // PerftTestResult(11030083, captures: 940350),
    ],
  ),
  PerftTestCase(
    "Position 4",
    "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    [
      PerftTestResult(6, captures: 0),
      PerftTestResult(264, captures: 87),
      PerftTestResult(9467, captures: 1021),
      PerftTestResult(422333, captures: 131393),
      // PerftTestResult(15833292, captures: 2046173),
    ],
  ),
  PerftTestCase(
    "Position 5",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    [
      PerftTestResult(44),
      PerftTestResult(1486),
      PerftTestResult(62379),
      // PerftTestResult(2103487),
      // 89941194,
    ],
  ),
  PerftTestCase(
    "Position 6",
    "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
    [
      PerftTestResult(46),
      PerftTestResult(2079),
      PerftTestResult(89890),
      // PerftTestResult(3894594),
      // 164075551,
    ],
  ),
];

void main() {
  for (final id in EngineRegistry.allIds) {
    group('Engine $id', () {
      for (final testCase in _testCases) {
        group(testCase.name, () {
          for (int depth = 1; depth <= testCase.expectedCounts.length; depth++) {
            test('depth $depth', () {
              final engine = EngineRegistry.create(id);
              final result = engine.perft(testCase.fen, depth);
              expect(result.nodes, testCase.expectedCounts[depth - 1].nodes);
              if (testCase.expectedCounts[depth - 1].captures != null) {
                expect(result.captures, testCase.expectedCounts[depth - 1].captures);
              }
            });
          }
        });
      }
    });
  }
}
