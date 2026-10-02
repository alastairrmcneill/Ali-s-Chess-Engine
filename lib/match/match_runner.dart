import 'package:ace/engines/engine_interface.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/match_config.dart';
import 'package:ace/match/match_stats.dart';
import 'package:ace/match/opening_book.dart';

class MatchRunner {
  final MatchConfig config;

  /// Called after every game, e.g. to write the PGN and print progress.
  final void Function(GameRecord record, MatchStats statsSoFar)? onGameFinished;

  /// Checked between games; return true to stop early (e.g. after Ctrl-C).
  final bool Function()? shouldStop;

  /// Warnings about the schedule (e.g. openings being reused).
  final List<String> warnings = [];

  MatchRunner(this.config, {this.onGameFinished, this.shouldStop});

  /// Plays the match. Opening p is played twice: game 2p+1 with A as White, game 2p+2 with B as White.
  /// Interleaving the pair means a match stopped half-way is still fair.
  Future<MatchStats> run({
    required OpeningBook book,
    required ChessEngine engineA,
    required ChessEngine engineB,
  }) async {
    config.validate();
    if (book.openings.isEmpty) throw ArgumentError('The opening book has no usable openings');

    final pairs = config.games ~/ 2;
    if (book.openings.length < pairs) {
      warnings.add('Only ${book.openings.length} openings for $pairs pairs: openings will be reused');
    }

    final stats = MatchStats(engineA.displayName, engineB.displayName, config.moveTime);
    final limits = SearchLimits(moveTime: config.moveTime);

    for (int pair = 0; pair < pairs; pair++) {
      final opening = book.openings[pair % book.openings.length];
      for (final aIsWhite in [true, false]) {
        if (shouldStop?.call() ?? false) return stats;
        final record = await GameRunner.playGame(
          gameNumber: stats.gamesPlayed + 1,
          opening: opening,
          white: aIsWhite ? engineA : engineB,
          black: aIsWhite ? engineB : engineA,
          engineAIsWhite: aIsWhite,
          limits: limits,
          maxEnginePlies: config.maxEnginePlies,
        );
        stats.add(record);
        onGameFinished?.call(record, stats);
      }
    }
    return stats;
  }
}
