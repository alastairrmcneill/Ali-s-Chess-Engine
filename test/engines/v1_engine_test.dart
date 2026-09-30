import 'package:ace/chess_core/fen.dart';
import 'package:ace/engines/chess_engine.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/engines/v1/core/board.dart';
import 'package:ace/engines/v1/core/move.dart';
import 'package:ace/engines/v1/core/move_generator.dart';
import 'package:ace/engines/v1/core/zobrist.dart';
import 'package:flutter_test/flutter_test.dart';

import '../perft_positions.dart';

int perft(MoveGenerator moveGenerator, Board board, int depth) {
  List<Move> moves = moveGenerator.generateLegalMoves(board);
  if (depth == 1) return moves.length;

  int nodes = 0;
  for (Move move in moves) {
    board.makeMove(move);
    nodes += perft(moveGenerator, board, depth - 1);
    board.unMakeMove(move);
  }
  return nodes;
}

void main() {
  group("v1 adapter", () {
    test("finds mate in one", () async {
      ChessEngine engine = createEngine("v1");
      SearchResult result = await engine.search(
        const EnginePosition(startFen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"),
        const SearchLimits(moveTimeMs: 200),
      );
      expect(result.bestMove, "a1a8");
      expect(result.mateIn, 1);
      expect(result.depth, greaterThanOrEqualTo(1));
      expect(result.pv.first, "a1a8");
    });

    test("plays from a start FEN plus moves and reports search info", () async {
      ChessEngine engine = createEngine("v1");
      SearchResult result = await engine.search(
        const EnginePosition(startFen: FenPosition.startingFen, uciMoves: ["e2e4", "e7e5", "g1f3"]),
        const SearchLimits(moveTimeMs: 100),
      );
      expect(result.bestMove, isNotNull);
      expect(result.scoreCp, isNotNull);
      expect(result.nodes, greaterThan(0));
      expect(result.pv, isNotEmpty);
      expect(result.pv.first, result.bestMove);
    });
  });

  // v1 is frozen, including its move generator. These counts pin down its current behaviour so any accidental
  // change to the snapshot is caught. The one known wrong count is documented in docs/engine_v1_known_issues.md.
  group("v1 perft (frozen behaviour)", () {
    Zobrist();
    const Map<String, List<int>> knownV1Differences = {
      "position 3": [14, 191, 2812, 43238, 674630], // Correct depth 5 count is 674624
    };

    for (PerftCase perftCase in perftCases) {
      test(perftCase.name, () {
        List<int> expected = knownV1Differences[perftCase.name] ?? perftCase.expected;
        for (int depth = 1; depth <= expected.length; depth++) {
          Board board = Board.fromFen(perftCase.fen);
          expect(perft(MoveGenerator(), board, depth), expected[depth - 1], reason: "depth $depth");
        }
      });
    }
  });
}
