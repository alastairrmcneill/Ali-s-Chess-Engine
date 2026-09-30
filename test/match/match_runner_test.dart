import 'dart:io';

import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_runner.dart';
import 'package:ace/match/match_storage.dart';
import 'package:ace/match/opening_book_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("labels players uniquely", () {
    MatchConfig same = MatchConfig(engine1Id: "v1", engine2Id: "v1");
    expect([same.engine1.label, same.engine2.label], ["ACE v1 (1)", "ACE v1 (2)"]);

    MatchConfig handicap = MatchConfig(engine1Id: "v1", engine2Id: "v1", moveTimeMs: 20, engine2MoveTimeMs: 200);
    expect([handicap.engine1.label, handicap.engine2.label], ["ACE v1 @20ms", "ACE v1 @200ms"]);

    expect(MatchConfig(engine1Id: "v1", engine2Id: "v1", games: 7).games, 8);
    expect(() => MatchConfig(engine1Id: "v1", engine2Id: "nope"), throwsArgumentError);
  });

  test("plays a short match on worker isolates and saves it", () async {
    MatchConfig config = MatchConfig(engine1Id: "v1", engine2Id: "v1", moveTimeMs: 20, games: 4, concurrency: 2);
    Directory root = await Directory.systemTemp.createTemp("ace_match_test");
    MatchRecorder recorder = await MatchRecorder.create(root, config);
    MatchRunner runner = MatchRunner(config);

    List<Future<void>> writes = [];
    int liveMoves = 0;
    runner.events.listen((event) {
      if (event is GameFinished) writes.add(recorder.addGame(event.game));
      if (event is LiveMove) liveMoves++;
    });
    await runner.run();
    await Future.wait(writes);
    await recorder.finish(runner.finishedGames, complete: runner.isComplete);

    expect(runner.isComplete, isTrue);
    expect(liveMoves, greaterThan(0));
    List<GameRecord> games = runner.finishedGames..sort((a, b) => a.gameNumber.compareTo(b.gameNumber));
    expect(games.map((game) => game.gameNumber), [1, 2, 3, 4]);

    // Games 1 and 2 share an opening with colours swapped
    expect(games[0].openingIndex, games[1].openingIndex);
    expect(games[0].white.label, games[1].black.label);
    expect(games[0].moves.take(16).map((move) => move.uci).join(" "), openingBook[games[0].openingIndex]);
    expect(games[0].moves.take(16).every((move) => move.book), isTrue);
    for (GameRecord game in games) {
      expect(["1-0", "0-1", "1/2-1/2"], contains(game.result));
      // v1 can fail to return a move at very short think times on a loaded machine (known issue #8), which ends the
      // game straight after the book moves
      expect(game.moves.length > 16 || game.termination == Termination.noMove, isTrue);
    }

    SavedMatch saved = (await SavedMatch.list(root)).single;
    expect(saved.complete, isTrue);
    List<GameRecord> loaded = await saved.loadGames();
    expect(loaded.map((game) => game.toJson()), games.map((game) => game.toJson()));
    expect(await saved.reportFile.readAsString(), contains("Games played: 4"));

    await root.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
