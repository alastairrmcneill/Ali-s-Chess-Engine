import 'package:ace/engines/random/random_engine.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_config.dart';
import 'package:ace/match/match_runner.dart';
import 'package:ace/match/opening_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final book = OpeningBook.fromUciLines(['e2e4 e7e5', 'd2d4 d7d5', 'c2c4 c7c5']);

  MatchConfig config(int games) => MatchConfig(
        engineAId: 'random',
        engineBId: 'random',
        games: games,
        moveTime: const Duration(milliseconds: 1),
        maxMoves: 20,
      );

  test('each opening is played twice, colours swapped and interleaved', () async {
    final records = <GameRecord>[];
    final runner = MatchRunner(config(6), onGameFinished: (record, _) => records.add(record));
    final stats = await runner.run(book: book, engineA: RandomEngine(seed: 1), engineB: RandomEngine(seed: 2));

    expect(records.map((r) => r.openingIndex), [0, 0, 1, 1, 2, 2]);
    expect(records.map((r) => r.engineAIsWhite), [true, false, true, false, true, false]);
    expect(records.map((r) => r.gameNumber), [1, 2, 3, 4, 5, 6]);
    expect(stats.gamesPlayed, 6);
    expect(stats.aAsWhite.games, 3);
    expect(runner.warnings, isEmpty);
  });

  test('openings are reused, with a warning, when there are too few', () async {
    final records = <GameRecord>[];
    final runner = MatchRunner(config(8), onGameFinished: (record, _) => records.add(record));
    await runner.run(book: book, engineA: RandomEngine(seed: 1), engineB: RandomEngine(seed: 2));
    expect(records.map((r) => r.openingIndex), [0, 0, 1, 1, 2, 2, 0, 0]);
    expect(runner.warnings, isNotEmpty);
  });

  test('an odd number of games is rejected', () {
    expect(() => MatchRunner(config(5)).run(book: book, engineA: RandomEngine(), engineB: RandomEngine()),
        throwsArgumentError);
  });

  test('stops between games when asked', () async {
    var played = 0;
    final runner = MatchRunner(config(6), onGameFinished: (_, __) => played++, shouldStop: () => played >= 3);
    final stats = await runner.run(book: book, engineA: RandomEngine(), engineB: RandomEngine());
    expect(stats.gamesPlayed, 3);
  });
}
