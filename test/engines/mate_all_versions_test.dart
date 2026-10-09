import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class MateTestCase {
  final String name;
  final String fen;
  final String bestMove; // the only move that forces mate, checked by brute force
  final int depth; // plies needed to see the mate: 2 for mate in 1, 4 for mate in 2 (with a margin)

  MateTestCase(this.name, this.fen, this.bestMove, this.depth);
}

// Engines that do not search, so they cannot be expected to find a mate.
const _nonSearchingEngines = {'v0'};

final List<MateTestCase> _mateInOne = [
  MateTestCase(
    "Scholar's mate, white",
    "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4",
    "h5f7",
    2,
  ),
  MateTestCase("Back rank, white", "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", "a1a8", 2),
  MateTestCase(
    "Fool's mate, black",
    "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2",
    "d8h4",
    2,
  ),
  MateTestCase("Back rank, black", "4r1k1/8/8/8/8/8/5PPP/6K1 b - - 0 1", "e8e1", 2),
];

// Both are 1.Ra6! (or ...Ra3!) sacrificing the rook so the pawn can mate; no mate in 1 exists.
final List<MateTestCase> _mateInTwo = [
  MateTestCase("Rook sacrifice, white", "kbK5/pp6/1P6/8/8/8/8/R7 w - - 0 1", "a1a6", 4),
  MateTestCase("Rook sacrifice, black", "r7/8/8/8/8/1p6/PP6/KBk5 b - - 0 1", "a8a3", 4),
];

void _runCases(String id, List<MateTestCase> cases) {
  for (final testCase in cases) {
    test(testCase.name, () {
      final engine = EngineRegistry.create(id)..newGame();
      final result = engine.getMove(
        testCase.fen,
        [],
        SearchLimits(moveTime: const Duration(seconds: 30), depth: testCase.depth),
      );
      expect(result.uciMove, testCase.bestMove);
    });
  }
}

void main() {
  for (final id in EngineRegistry.allIds.where((id) => !_nonSearchingEngines.contains(id))) {
    group('Engine $id', () {
      group('mate in 1', () => _runCases(id, _mateInOne));
      group('mate in 2', () => _runCases(id, _mateInTwo));
    });
  }
}
