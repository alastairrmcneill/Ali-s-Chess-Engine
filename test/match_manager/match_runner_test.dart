import 'package:ace/chess_core/game_end.dart';
import 'package:ace/match_manager/match_config.dart';
import 'package:ace/match_manager/match_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_engines.dart';

void main() {
  test('schedules each opening twice with colours swapped and aggregates results from A\'s point of view', () async {
    final config = MatchConfig(engineAId: 'illegalA', engineBId: 'illegalB', games: 6);
    final runner = MatchRunner(config);

    final stats = await runner.runMatch(engineA: IllegalEngine(), engineB: IllegalEngine());

    // Every opening line is 16 plies (even), so White is always the first engine asked to move,
    // and IllegalEngine always forfeits immediately. So whichever engine is White loses.
    expect(stats.gamesPlayed, 6);
    expect(stats.total.wins, 3); // A wins the 3 games where A was Black
    expect(stats.total.losses, 3); // A loses the 3 games where A was White
    expect(stats.total.draws, 0);
    expect(stats.aAsWhite.losses, 3);
    expect(stats.aAsWhite.wins, 0);
    expect(stats.aAsBlack.wins, 3);
    expect(stats.aAsBlack.losses, 0);
    expect(stats.terminations[GameTermination.illegalMove], 6);
  });

  test('an odd games count is rounded down to a whole number of pairs', () async {
    final config = MatchConfig(engineAId: 'illegalA', engineBId: 'illegalB', games: 7);
    final runner = MatchRunner(config);

    final stats = await runner.runMatch(engineA: IllegalEngine(), engineB: IllegalEngine());

    expect(stats.gamesPlayed, 6); // 7 ~/ 2 == 3 pairs == 6 games, the 7th game is dropped
  });
}
