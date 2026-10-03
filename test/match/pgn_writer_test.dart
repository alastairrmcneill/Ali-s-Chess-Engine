import 'package:ace/match/pgn_writer.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/chess_core/game_end.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PgnWriter.formatEval', () {
    test('formats positive eval in pawns', () {
      expect(PgnWriter.formatEval(50), '+0.50');
      expect(PgnWriter.formatEval(100), '+1.00');
      expect(PgnWriter.formatEval(250), '+2.50');
    });

    test('formats negative eval in pawns', () {
      expect(PgnWriter.formatEval(-50), '-0.50');
      expect(PgnWriter.formatEval(-100), '-1.00');
      expect(PgnWriter.formatEval(-250), '-2.50');
    });

    test('formats zero eval', () {
      expect(PgnWriter.formatEval(0), '+0.00');
    });

    test('formats mate score as +M', () {
      expect(PgnWriter.formatEval(1000000000), '+M');
      expect(PgnWriter.formatEval(900000001), '+M');
    });

    test('formats mate loss score as -M', () {
      expect(PgnWriter.formatEval(-1000000000), '-M');
      expect(PgnWriter.formatEval(-900000001), '-M');
    });

    test('formats edge case around mateThreshold', () {
      // 899999999 is below mateThreshold (900000000)
      const eval = 900000000 - 1; // 899999999
      final formatted = PgnWriter.formatEval(eval);
      expect(formatted, '+8999999.99');

      const negEval = -(900000000 - 1); // -899999999
      final negFormatted = PgnWriter.formatEval(negEval);
      expect(negFormatted, '-8999999.99');
    });

    test('handles small positive values', () {
      expect(PgnWriter.formatEval(1), '+0.01');
      expect(PgnWriter.formatEval(10), '+0.10');
    });

    test('handles small negative values', () {
      expect(PgnWriter.formatEval(-1), '-0.01');
      expect(PgnWriter.formatEval(-10), '-0.10');
    });
  });

  group('PgnWriter.gameToPgn', () {
    late GameRecord record;

    setUp(() {
      record = const GameRecord(
        gameNumber: 1,
        openingIndex: 0,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 2,
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
        moveStats: [
          MoveStat(100, 20, 50000, 50),
        ],
        duration: Duration(milliseconds: 500),
      );
    });

    test('generates PGN with required headers', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test Match',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('[Event "Test Match"]'));
      expect(pgn, contains('[Site "ACE match manager"]'));
      expect(pgn, contains('[White "Engine V1"]'));
      expect(pgn, contains('[Black "Engine V2"]'));
      expect(pgn, contains('[Result "1-0"]'));
    });

    test('includes round number from gameNumber', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('[Round "1"]'));
    });

    test('includes opening index', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('[Opening "book #1"]'));
    });

    test('includes move count', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('[PlyCount "3"]'));
    });

    test('includes time control with moveTime', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('[TimeControl "movetime=100ms"]'));
    });

    test('includes moves with alternating numbers', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('1.'));
      expect(pgn, contains('e4'));
      expect(pgn, contains('c5'));
    });

    test('marks book moves with {book}', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      // First 2 moves (c5) are book moves, should have {book} after 2nd move
      expect(pgn, contains('c5 {book}'));
    });

    test('includes engine comments for engine moves', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('{'));
      expect(pgn, contains('100ms'));
    });

    test('includes termination reason', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('[Termination "checkmate"]'));
    });

    test('includes result at end of moves', () {
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('1-0'));
    });

    test('handles draw result', () {
      const drawRecord = GameRecord(
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
          outcome: GameOutcome.draw,
          termination: GameTermination.threefoldRepetition,
        ),
        uciMoves: [],
        sanMoves: [],
        moveStats: [],
        duration: Duration(seconds: 1),
      );
      final pgn = PgnWriter.gameToPgn(
        drawRecord,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('[Result "1/2-1/2"]'));
      expect(pgn, contains('1/2-1/2'));
    });

    test('handles black win', () {
      const blackWinRecord = GameRecord(
        gameNumber: 3,
        openingIndex: 2,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 0,
        whiteId: 'v1',
        blackId: 'v2',
        whiteName: 'Engine V1',
        blackName: 'Engine V2',
        engineAIsWhite: true,
        end: GameEnd(
          outcome: GameOutcome.blackWin,
          termination: GameTermination.checkmate,
        ),
        uciMoves: [],
        sanMoves: [],
        moveStats: [],
        duration: Duration(seconds: 1),
      );
      final pgn = PgnWriter.gameToPgn(
        blackWinRecord,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('[Result "0-1"]'));
      expect(pgn, contains('0-1'));
    });

    test('uses provided date or defaults to now', () {
      final date = DateTime(2023, 6, 15);
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
        date: date,
      );
      expect(pgn, contains('[Date "2023.06.15"]'));
    });

    test('includes forfeit detail for illegal moves', () {
      const illegalRecord = GameRecord(
        gameNumber: 4,
        openingIndex: 0,
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
          detail: 'Illegal move: a1a1',
        ),
        uciMoves: [],
        sanMoves: [],
        moveStats: [],
        duration: Duration(seconds: 1),
      );
      final pgn = PgnWriter.gameToPgn(
        illegalRecord,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('{forfeit:'));
      expect(pgn, contains('Illegal move'));
    });

    test('escapes special characters in headers', () {
      const specialRecord = GameRecord(
        gameNumber: 5,
        openingIndex: 0,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 0,
        whiteId: 'v1',
        blackId: 'v2',
        whiteName: 'Engine "Special" V1',
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
      final pgn = PgnWriter.gameToPgn(
        specialRecord,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('\\'));
    });
  });

  group('PgnWriter move comments', () {
    test('formats move stat with all fields', () {
      // This tests the internal _comment method indirectly
      const record = GameRecord(
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
        uciMoves: ['e2e4'],
        sanMoves: ['e4'],
        moveStats: [MoveStat(123, 25, 456789, 75)],
        duration: Duration(seconds: 1),
      );
      final pgn = PgnWriter.gameToPgn(
        record,
        event: 'Test',
        moveTime: const Duration(milliseconds: 100),
      );
      expect(pgn, contains('{'));
      expect(pgn, contains('123ms'));
    });
  });
}
