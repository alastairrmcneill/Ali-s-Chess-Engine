import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/engines/v1/v1_engine.dart';
import 'package:ace/chess_core/notation/fen.dart';
import 'package:flutter_test/flutter_test.dart';

final _uciMoveRegExp = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

// Per-version helpers for checking that a move is in the engine's own legal move list.
// Only v1 is wired up today; future versions can add their own entry here.
final _ownLegalMoves = <String, Set<String> Function(String fen, List<String> uciMoves)>{
  'v1': (fen, uciMoves) {
    final board = Board.fromFEN(fen);
    for (final uciMove in uciMoves) {
      board.makeMove(
        MoveGenerator().generateLegalMoves(board).firstWhere((m) => V1Engine().moveToUci(m) == uciMove),
      );
    }
    return MoveGenerator().generateLegalMoves(board).map((m) => V1Engine().moveToUci(m)).toSet();
  },
};

void main() {
  for (final id in EngineRegistry.allIds) {
    group('Engine: $id', () {
      final limits = SearchLimits(moveTime: const Duration(milliseconds: 50));

      test('returns a well-formed, legal UCI move from the start position', () async {
        final engine = EngineRegistry.create(id);
        final result = await engine.getMove(FenPosition.startingPosition, [], limits);

        expect(result.uciMove, matches(_uciMoveRegExp));

        final legalMoves = _ownLegalMoves[id];
        if (legalMoves != null) {
          expect(legalMoves(FenPosition.startingPosition, []), contains(result.uciMove));
        }
      });

      test('promotes when the only reasonable move is a pawn push to the back rank', () async {
        final engine = EngineRegistry.create(id);
        final result = await engine.getMove('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1', [], limits);

        expect(result.uciMove, startsWith('b7b8'));
        expect(result.uciMove, hasLength(5));
      });

      test('replaying a history that includes castling does not throw', () async {
        final engine = EngineRegistry.create(id);
        await engine.getMove(
          FenPosition.startingPosition,
          ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'e1g1'],
          limits,
        );
      });

      test('replaying an en passant line does not throw', () async {
        final engine = EngineRegistry.create(id);
        await engine.getMove(
          FenPosition.startingPosition,
          ['e2e4', 'a7a6', 'e4e5', 'd7d5', 'e5d6'],
          limits,
        );
      });

      test('an unknown/illegal move in the history throws StateError', () async {
        final engine = EngineRegistry.create(id);
        await expectLater(
          () => engine.getMove(FenPosition.startingPosition, ['e2e5'], limits),
          throwsStateError,
        );
      });

      test('getMove can be called twice on the same instance, with newGame() in between', () async {
        final engine = EngineRegistry.create(id);

        final first = await engine.getMove(FenPosition.startingPosition, [], limits);
        expect(first.uciMove, matches(_uciMoveRegExp));

        await engine.newGame();

        final second = await engine.getMove(FenPosition.startingPosition, [], limits);
        expect(second.uciMove, matches(_uciMoveRegExp));
      });
    });
  }
}
