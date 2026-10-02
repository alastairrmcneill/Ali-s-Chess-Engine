import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/random/random_engine.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/opening_book.dart';
import 'package:ace/match/pgn_reader.dart';
import 'package:ace/match/pgn_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_engines.dart';

Future<GameRecord> _randomGame(int seed) => GameRunner.playGame(
      gameNumber: seed,
      opening: const Opening(3, ['e2e4', 'c7c5']),
      white: RandomEngine(seed: seed),
      black: RandomEngine(seed: seed + 100),
      engineAIsWhite: true,
      limits: const SearchLimits(moveTime: Duration(milliseconds: 1)),
      maxEnginePlies: 200,
    );

void main() {
  group('PgnWriter', () {
    test('headers, book marker, move numbers and result', () async {
      final record = await GameRunner.playGame(
        gameNumber: 12,
        opening: const Opening(0, ['f2f3']),
        white: ScriptedEngine(['g2g4']),
        black: ScriptedEngine(['e7e5', 'd8h4']),
        engineAIsWhite: true,
        limits: const SearchLimits(moveTime: Duration(milliseconds: 100)),
        maxEnginePlies: 600,
      );
      final pgn = PgnWriter.gameToPgn(record, event: 'test', moveTime: const Duration(milliseconds: 100));
      expect(pgn, contains('[Round "12"]'));
      expect(pgn, contains('[Result "0-1"]'));
      expect(pgn, contains('[Termination "checkmate"]'));
      expect(pgn, contains('1. f3 {book} e5 {+0.00/1 '));
      expect(pgn, contains('2. g4'));
      expect(pgn, contains('Qh4#'));
      expect(pgn.trim(), endsWith('0-1'));
    });

    test('forfeits get a comment', () async {
      final record = await GameRunner.playGame(
        gameNumber: 1,
        opening: const Opening(0, []),
        white: IllegalEngine(),
        black: RandomEngine(),
        engineAIsWhite: true,
        limits: const SearchLimits(moveTime: Duration(milliseconds: 1)),
        maxEnginePlies: 600,
      );
      expect(record.end.termination, GameTermination.illegalMove);
      expect(PgnWriter.gameToPgn(record, event: 'x', moveTime: Duration.zero), contains('{forfeit: illegal played "e2e5"'));
    });

    test('eval formatting', () {
      expect(PgnWriter.formatEval(31), '+0.31');
      expect(PgnWriter.formatEval(-250), '-2.50');
      expect(PgnWriter.formatEval(999999990), '+M');
    });

    test('round trip: written games read back to the same moves', () async {
      for (int seed = 1; seed <= 10; seed++) {
        final record = await _randomGame(seed);
        final text = PgnWriter.gameToPgn(record, event: 'round trip', moveTime: Duration.zero);
        final game = PgnReader.parseMany(text).single;
        expect(game.result, record.end.pgnResult);
        expect(game.headers['Round'], '$seed');

        final referee = Referee(Referee.standardStartFen, maxPlies: 1 << 30);
        for (final san in game.sanMoves) {
          expect(referee.tryPlaySan(san), isNull, reason: 'seed $seed: $san');
        }
        expect(referee.uciHistory, record.uciMoves);
      }
    });
  });

  group('PgnReader', () {
    test('comments, nested variations, NAGs and move numbers', () {
      final games = PgnReader.parseMany('1. e4 {best by test} e5 (1... c5 2. Nf3 (2. c3)) 2. Nf3 \$1 ; comment\n2... Nc6 *');
      expect(games.single.sanMoves, ['e4', 'e5', 'Nf3', 'Nc6']);
      expect(games.single.result, '*');
    });

    test('several games, with and without headers', () {
      const text = '[Event "one"]\n[White "A"]\n\n1.e4 e5 2.Nf3 1-0\n\n[Event "two"]\n\n1. d4 {multi\nline comment} d5 0-1\n'
          '1. c4 c5 1/2-1/2';
      final games = PgnReader.parseMany(text);
      expect(games, hasLength(3));
      expect(games[0].headers, {'Event': 'one', 'White': 'A'});
      expect(games[0].sanMoves, ['e4', 'e5', 'Nf3']);
      expect(games[1].sanMoves, ['d4', 'd5']);
      expect(games[2].result, '1/2-1/2');
    });
  });
}
