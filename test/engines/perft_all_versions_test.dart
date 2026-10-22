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
      PerftTestResult(20),
      PerftTestResult(400),
      PerftTestResult(8902),
      PerftTestResult(197281),
      PerftTestResult(4865609),
    ],
  ),
  PerftTestCase(
    "Kiwipete",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    [
      PerftTestResult(48),
      PerftTestResult(2039),
      PerftTestResult(97862),
      PerftTestResult(4085603),
    ],
  ),
  PerftTestCase(
    "Position 3",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    [
      PerftTestResult(14),
      PerftTestResult(191),
      PerftTestResult(2812),
      PerftTestResult(43238),
      PerftTestResult(674624),
      PerftTestResult(11030083),
    ],
  ),
  PerftTestCase(
    "Position 4",
    "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    [
      PerftTestResult(6),
      PerftTestResult(264),
      PerftTestResult(9467),
      PerftTestResult(422333),
      PerftTestResult(15833292),
    ],
  ),
  PerftTestCase(
    "Position 5",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    [
      PerftTestResult(44),
      PerftTestResult(1486),
      PerftTestResult(62379),
      PerftTestResult(2103487),
      PerftTestResult(89941194),
    ],
  ),
  PerftTestCase(
    "Position 6",
    "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
    [
      PerftTestResult(46),
      PerftTestResult(2079),
      PerftTestResult(89890),
      PerftTestResult(3894594),
      PerftTestResult(164075551),
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
            });
          }
        });
      }
    });
  }
}
