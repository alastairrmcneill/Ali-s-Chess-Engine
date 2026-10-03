import 'package:ace/match/game_record.dart';
import 'package:ace/chess_core/game_end.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoveStat', () {
    test('creates with all fields', () {
      final stat = MoveStat(100, 20, 50000, 50);
      expect(stat.timeMs, 100);
      expect(stat.depth, 20);
      expect(stat.nodes, 50000);
      expect(stat.evaluation, 50);
    });

    test('creates with null optional fields', () {
      final stat = MoveStat(200, null, null, null);
      expect(stat.timeMs, 200);
      expect(stat.depth, isNull);
      expect(stat.nodes, isNull);
      expect(stat.evaluation, isNull);
    });

    test('toString includes all fields', () {
      final stat = MoveStat(150, 25, 100000, -30);
      final str = stat.toString();
      expect(str, contains('timeMs: 150'));
      expect(str, contains('depth: 25'));
      expect(str, contains('nodes: 100000'));
      expect(str, contains('evaluation: -30'));
    });

    test('handles negative evaluation', () {
      final stat = MoveStat(50, 15, 30000, -100);
      expect(stat.evaluation, -100);
    });

    test('handles large node counts', () {
      final stat = MoveStat(500, 30, 10000000, 0);
      expect(stat.nodes, 10000000);
    });
  });

  group('GameRecord', () {
    late GameRecord record;

    setUp(() {
      record = GameRecord(
        gameNumber: 1,
        openingIndex: 0,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 16,
        whiteId: 'v1',
        blackId: 'v2',
        whiteName: 'Engine V1',
        blackName: 'Engine V2',
        engineAIsWhite: true,
        end: GameEnd(
          outcome: GameOutcome.whiteWin,
          termination: GameTermination.checkmate,
        ),
        uciMoves: ['e2e4', 'c7c5', 'g1f3'],
        sanMoves: ['e4', 'c5', 'Nf3'],
        moveStats: [MoveStat(100, 20, 50000, 50)],
        duration: Duration(seconds: 5),
      );
    });

    test('creates with all required fields', () {
      expect(record.gameNumber, 1);
      expect(record.openingIndex, 0);
      expect(record.bookPlies, 16);
      expect(record.whiteId, 'v1');
      expect(record.blackId, 'v2');
      expect(record.whiteName, 'Engine V1');
      expect(record.blackName, 'Engine V2');
      expect(record.engineAIsWhite, true);
      expect(record.end.outcome, GameOutcome.whiteWin);
    });

    test('stores error detail when present', () {
      final errorRecord = GameRecord(
        gameNumber: 2,
        openingIndex: 1,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 0,
        whiteId: 'v1',
        blackId: 'v2',
        whiteName: 'Engine V1',
        blackName: 'Engine V2',
        engineAIsWhite: true,
        end: GameEnd(
          outcome: GameOutcome.blackWin,
          termination: GameTermination.illegalMove,
          detail: 'Engine returned illegal move: a1a1',
        ),
        uciMoves: const [],
        sanMoves: const [],
        moveStats: const [],
        errorDetail: 'Stack trace here',
        duration: Duration(seconds: 1),
      );
      expect(errorRecord.errorDetail, 'Stack trace here');
    });

    group('engineMoveIsWhite', () {
      test('correctly determines white moves from even ply indices', () {
        // bookPlies = 16, so engine moves start at ply 16
        // Ply 16 (even) = white plays
        expect(record.engineMoveIsWhite(0), true);
        // Ply 17 (odd) = black plays
        expect(record.engineMoveIsWhite(1), false);
        // Ply 18 (even) = white plays
        expect(record.engineMoveIsWhite(2), true);
      });

      test('engineMoveIsWhite is true when bookPlies is even', () {
        // Even bookPlies: white makes first engine move
        final rec = GameRecord(
          gameNumber: 1,
          openingIndex: 0,
          startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          bookPlies: 16, // even
          whiteId: 'v1',
          blackId: 'v2',
          whiteName: 'Engine V1',
          blackName: 'Engine V2',
          engineAIsWhite: true,
          end: GameEnd(
            outcome: GameOutcome.whiteWin,
            termination: GameTermination.checkmate,
          ),
          uciMoves: [],
          sanMoves: [],
          moveStats: [],
          duration: Duration(seconds: 1),
        );
        expect(rec.engineMoveIsWhite(0), true);
      });

      test('engineMoveIsWhite is false when bookPlies is odd', () {
        // Odd bookPlies: black makes first engine move
        final rec = GameRecord(
          gameNumber: 1,
          openingIndex: 0,
          startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          bookPlies: 15, // odd
          whiteId: 'v1',
          blackId: 'v2',
          whiteName: 'Engine V1',
          blackName: 'Engine V2',
          engineAIsWhite: true,
          end: GameEnd(
            outcome: GameOutcome.whiteWin,
            termination: GameTermination.checkmate,
          ),
          uciMoves: [],
          sanMoves: [],
          moveStats: [],
          duration: Duration(seconds: 1),
        );
        expect(rec.engineMoveIsWhite(0), false);
      });

      test('engineMoveIsWhite alternates correctly', () {
        for (int i = 0; i < 10; i++) {
          final expected = (record.bookPlies + i).isEven;
          expect(record.engineMoveIsWhite(i), expected);
        }
      });
    });

    group('game properties', () {
      test('tracks game number', () {
        final rec1 = GameRecord(
          gameNumber: 1,
          openingIndex: 0,
          startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          bookPlies: 0,
          whiteId: 'v1',
          blackId: 'v2',
          whiteName: 'V1',
          blackName: 'V2',
          engineAIsWhite: true,
          end: GameEnd(
            outcome: GameOutcome.whiteWin,
            termination: GameTermination.checkmate,
          ),
          uciMoves: [],
          sanMoves: [],
          moveStats: [],
          duration: Duration(seconds: 1),
        );
        final rec100 = GameRecord(
          gameNumber: 100,
          openingIndex: 0,
          startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          bookPlies: 0,
          whiteId: 'v1',
          blackId: 'v2',
          whiteName: 'V1',
          blackName: 'V2',
          engineAIsWhite: true,
          end: GameEnd(
            outcome: GameOutcome.whiteWin,
            termination: GameTermination.checkmate,
          ),
          uciMoves: [],
          sanMoves: [],
          moveStats: [],
          duration: Duration(seconds: 1),
        );
        expect(rec1.gameNumber, 1);
        expect(rec100.gameNumber, 100);
      });

      test('tracks opening index', () {
        final rec = GameRecord(
          gameNumber: 1,
          openingIndex: 42,
          startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          bookPlies: 0,
          whiteId: 'v1',
          blackId: 'v2',
          whiteName: 'V1',
          blackName: 'V2',
          engineAIsWhite: true,
          end: GameEnd(
            outcome: GameOutcome.whiteWin,
            termination: GameTermination.checkmate,
          ),
          uciMoves: [],
          sanMoves: [],
          moveStats: [],
          duration: Duration(seconds: 1),
        );
        expect(rec.openingIndex, 42);
      });

      test('tracks duration', () {
        final rec = GameRecord(
          gameNumber: 1,
          openingIndex: 0,
          startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          bookPlies: 0,
          whiteId: 'v1',
          blackId: 'v2',
          whiteName: 'V1',
          blackName: 'V2',
          engineAIsWhite: true,
          end: GameEnd(
            outcome: GameOutcome.whiteWin,
            termination: GameTermination.checkmate,
          ),
          uciMoves: [],
          sanMoves: [],
          moveStats: [],
          duration: Duration(minutes: 5, seconds: 30),
        );
        expect(rec.duration.inMilliseconds, 330000);
      });
    });

    test('toString includes key information', () {
      final str = record.toString();
      expect(str, contains('GameRecord'));
      expect(str, isNotNull);
    });

    test('handles empty move lists', () {
      final rec = GameRecord(
        gameNumber: 1,
        openingIndex: 0,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 0,
        whiteId: 'v1',
        blackId: 'v2',
        whiteName: 'V1',
        blackName: 'V2',
        engineAIsWhite: true,
        end: GameEnd(
          outcome: GameOutcome.draw,
          termination: GameTermination.threefoldRepetition,
        ),
        uciMoves: [],
        sanMoves: [],
        moveStats: [],
        duration: Duration(milliseconds: 100),
      );
      expect(rec.uciMoves.length, 0);
      expect(rec.sanMoves.length, 0);
    });
  });
}
