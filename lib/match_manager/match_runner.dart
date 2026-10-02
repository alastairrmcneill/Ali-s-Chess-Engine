import 'package:ace/engines/engine_interface.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/opening_book.dart';
import 'package:ace/match_manager/match_config.dart';
import 'package:ace/match_manager/match_stats.dart';

class MatchRunner {
  final MatchConfig config;
  const MatchRunner(this.config);

  Future<MatchStats> runMatch({
    required ChessEngine engineA,
    required ChessEngine engineB,
  }) async {
    final pairs = config.games ~/ 2;

    final stats = MatchStats(
      engineA.displayName,
      engineB.displayName,
      config.moveTime,
    );
    final limits = SearchLimits(
      moveTime: config.moveTime,
    );

    for (int pair = 0; pair < pairs; pair++) {
      final opening = OpeningBook.standard().openings[pair];

      for (final aIsWhite in [true, false]) {
        final record = await GameRunner().playGame(
          gameNumber: pair * 2 + (aIsWhite ? 1 : 2),
          opening: opening,
          white: aIsWhite ? engineA : engineB,
          black: aIsWhite ? engineB : engineA,
          engineAIsWhite: aIsWhite,
          searchLimits: limits,
          maxPlies: config.maxPlies,
        );

        stats.add(record);
      }
    }
    return stats;
  }
}
