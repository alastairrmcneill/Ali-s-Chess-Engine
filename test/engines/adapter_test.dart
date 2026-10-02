import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/engines/v1/v1_engine.dart';
import 'package:flutter_test/flutter_test.dart';

final _uciMoveRegExp = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

// Per-version helpers for checking that a move is in the engine's own legal move list.
// Add an entry when you add a version.
final _ownLegalMoves = <String, Set<String> Function(String fen, List<String> uciMoves)>{
  'v1': V1Engine.legalUciMoves,
};

void main() {
  for (final id in EngineRegistry.versionIds) {
    group('Engine: $id', () {
      const limits = SearchLimits(moveTime: Duration(milliseconds: 50));

      test('returns a well-formed, legal UCI move from the start position', () async {
        final engine = EngineRegistry.create(id);
        final result = await engine.getMove(FenPosition.startingPosition, [], limits);

        expect(result.uciMove, matches(_uciMoveRegExp));

        final legalMoves = _ownLegalMoves[id];
        if (legalMoves != null) {
          expect(legalMoves(FenPosition.startingPosition, []), contains(result.uciMove));
        }
        expect(Referee(FenPosition.startingPosition).legalUciMoves(), contains(result.uciMove));
      });

      test('includes the promotion piece when the only legal moves are promotions', () async {
        final engine = EngineRegistry.create(id);
        // White's king is boxed in by the queen on b3, so c7-c8 (=Q/R/B/N) are the only legal moves.
        final result = await engine.getMove('7k/2P5/8/8/8/1q6/8/K7 w - - 0 1', [], limits);

        expect(result.uciMove, matches(RegExp(r'^c7c8[qrbn]$')));
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

      // Longer think time so at least one iteration completes even when tests run in parallel.
      const slowLimits = SearchLimits(moveTime: Duration(milliseconds: 300));

      test('reports the search depth', () async {
        final result = await EngineRegistry.create(id).getMove(FenPosition.startingPosition, [], slowLimits);
        expect(result.depth, isNotNull);
        expect(result.depth!, greaterThanOrEqualTo(1));
      });

      test('reports the eval from White\'s point of view', () async {
        final engine = EngineRegistry.create(id);
        // Black to move and a queen up: the eval should be clearly negative (good for Black).
        final result = await engine.getMove('4k3/8/8/8/8/8/3q4/K7 b - - 0 1', [], slowLimits);
        expect(result.evaluation, isNotNull);
        expect(result.evaluation!, lessThan(-500));
      });
    });
  }
}
