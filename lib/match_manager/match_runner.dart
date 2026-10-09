import 'package:ace/engines/engine_interface.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/opening_book.dart';
import 'package:ace/match_manager/match_config.dart';
import 'package:ace/match_manager/match_output.dart';
import 'package:ace/match_manager/match_stats.dart';

class MatchRunner {
  final MatchConfig config;
  late final MatchOutput _output;

  MatchRunner(this.config);

  Future<MatchStats> runMatch({
    required ChessEngine engineA,
    required ChessEngine engineB,
    required String engineAName,
    required String engineBName,
    required List<String> openingBookWarnings,
    void Function(GameRecord record, MatchStats stats)? onGameFinished,
  }) async {
    // Initialize output directory
    _output = MatchOutput.create(config, engineAName: engineAName, engineBName: engineBName);

    final pairs = config.games ~/ 2;

    final stats = MatchStats(
      engineAName,
      engineBName,
      config.moveTime,
      depth: config.depth,
    );
    final limits = SearchLimits(
      moveTime: config.moveTime,
      depth: config.depth,
    );

    final book = OpeningBook.standard();

    for (int pair = 0; pair < pairs; pair++) {
      final opening = book.openings[pair];

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
        _output.addGame(record);
        onGameFinished?.call(record, stats);
      }
    }

    // Write match summary files
    _output.writeConfig(openingCount: book.openings.length, warnings: [...book.warnings, ...openingBookWarnings]);
    _output.writeSummary(stats);
    _output.writeSummaryJson(stats);

    return stats;
  }
}
