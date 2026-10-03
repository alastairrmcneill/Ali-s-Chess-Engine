import 'package:ace/chess_core/game_end.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameOutcome and GameTermination enums', () {
    // This group ensures the enums have expected values
  });

  group('GameOutcome', () {
    test('has whiteWin, blackWin, and draw values', () {
      expect(GameOutcome.whiteWin, isNotNull);
      expect(GameOutcome.blackWin, isNotNull);
      expect(GameOutcome.draw, isNotNull);
    });
  });

  group('GameTermination', () {
    test('has all required termination reasons', () {
      expect(GameTermination.checkmate, isNotNull);
      expect(GameTermination.stalemate, isNotNull);
      expect(GameTermination.threefoldRepetition, isNotNull);
      expect(GameTermination.fiftyMoveRule, isNotNull);
      expect(GameTermination.insufficientMaterial, isNotNull);
      expect(GameTermination.maxMoves, isNotNull);
      expect(GameTermination.illegalMove, isNotNull);
      expect(GameTermination.engineError, isNotNull);
    });
  });

  group('GameEnd', () {
    test('creates with required fields', () {
      const end = GameEnd(
        outcome: GameOutcome.whiteWin,
        termination: GameTermination.checkmate,
      );
      expect(end.outcome, GameOutcome.whiteWin);
      expect(end.termination, GameTermination.checkmate);
      expect(end.detail, isNull);
    });

    test('creates with optional detail', () {
      const detail = 'Test detail';
      const end = GameEnd(
        outcome: GameOutcome.whiteWin,
        termination: GameTermination.checkmate,
        detail: detail,
      );
      expect(end.detail, detail);
    });

    group('pgnResult', () {
      test('returns "1-0" for whiteWin', () {
        const end = GameEnd(
          outcome: GameOutcome.whiteWin,
          termination: GameTermination.checkmate,
        );
        expect(end.pgnResult, '1-0');
      });

      test('returns "0-1" for blackWin', () {
        const end = GameEnd(
          outcome: GameOutcome.blackWin,
          termination: GameTermination.checkmate,
        );
        expect(end.pgnResult, '0-1');
      });

      test('returns "1/2-1/2" for draw', () {
        const end = GameEnd(
          outcome: GameOutcome.draw,
          termination: GameTermination.stalemate,
        );
        expect(end.pgnResult, '1/2-1/2');
      });
    });

    group('toString', () {
      test('includes outcome, termination, and detail', () {
        const end = GameEnd(
          outcome: GameOutcome.whiteWin,
          termination: GameTermination.checkmate,
          detail: 'Black king mated',
        );
        final str = end.toString();
        expect(str, contains('outcome'));
        expect(str, contains('whiteWin'));
        expect(str, contains('termination'));
        expect(str, contains('checkmate'));
        expect(str, contains('detail'));
        expect(str, contains('Black king mated'));
      });

      test('handles null detail gracefully', () {
        const end = GameEnd(
          outcome: GameOutcome.whiteWin,
          termination: GameTermination.checkmate,
        );
        final str = end.toString();
        expect(str, contains('null'));
      });
    });

    group('different terminations and outcomes', () {
      final testCases = [
        (GameOutcome.whiteWin, GameTermination.checkmate),
        (GameOutcome.whiteWin, GameTermination.maxMoves),
        (GameOutcome.blackWin, GameTermination.checkmate),
        (GameOutcome.blackWin, GameTermination.maxMoves),
        (GameOutcome.draw, GameTermination.stalemate),
        (GameOutcome.draw, GameTermination.threefoldRepetition),
        (GameOutcome.draw, GameTermination.fiftyMoveRule),
        (GameOutcome.draw, GameTermination.insufficientMaterial),
        (GameOutcome.whiteWin, GameTermination.illegalMove),
        (GameOutcome.blackWin, GameTermination.engineError),
      ];

      for (final (outcome, termination) in testCases) {
        test('creates GameEnd with $outcome and $termination', () {
          final end = GameEnd(outcome: outcome, termination: termination);
          expect(end.outcome, outcome);
          expect(end.termination, termination);
        });
      }
    });
  });
}
