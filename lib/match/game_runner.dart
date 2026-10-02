import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/opening_book.dart';

class GameRunner {
  /// Plays one game from the standard start position: the opening's book moves first, then the engines.
  /// [maxEnginePlies] counts only engine moves; when reached the game is drawn ([GameTermination.maxMoves]).
  static Future<GameRecord> playGame({
    required int gameNumber,
    required Opening opening,
    required ChessEngine white,
    required ChessEngine black,
    required bool engineAIsWhite,
    required SearchLimits limits,
    required int maxEnginePlies,
  }) async {
    final startFen = Referee.standardStartFen;
    final referee = Referee(startFen, maxPlies: opening.moves.length + maxEnginePlies);
    final stopwatch = Stopwatch()..start();
    final moveStats = <MoveStat>[];

    for (final move in opening.moves) {
      final reason = referee.tryPlayUci(move);
      if (reason != null) throw ArgumentError('Opening ${opening.index + 1} is invalid: $reason');
    }

    await white.newGame();
    await black.newGame();

    GameRecord record(GameEnd end, [String? errorDetail]) => GameRecord(
          gameNumber: gameNumber,
          openingIndex: opening.index,
          startFen: startFen,
          bookPlies: opening.moves.length,
          whiteId: white.id,
          blackId: black.id,
          whiteName: white.displayName,
          blackName: black.displayName,
          engineAIsWhite: engineAIsWhite,
          end: end,
          uciMoves: referee.uciHistory,
          sanMoves: referee.sanHistory,
          moveStats: List.unmodifiable(moveStats),
          errorDetail: errorDetail,
          duration: stopwatch.elapsed,
        );

    while (true) {
      final end = referee.checkGameEnd();
      if (end != null) return record(end);

      final mover = referee.whiteToMove ? white : black;
      final moverLoses = referee.whiteToMove ? GameOutcome.blackWin : GameOutcome.whiteWin;
      final moveStopwatch = Stopwatch()..start();

      EngineMoveResult result;
      try {
        // A fresh unmodifiable copy, so a buggy engine can't change the referee's history.
        result = await mover.getMove(startFen, referee.uciHistory, limits);
      } catch (e, stackTrace) {
        return record(
          GameEnd(outcome: moverLoses, termination: GameTermination.engineError, detail: '${mover.id}: $e'),
          '$e\n$stackTrace',
        );
      }
      moveStopwatch.stop();

      final uci = result.uciMove.trim().toLowerCase();
      final reason = referee.tryPlayUci(uci);
      if (reason != null) {
        final detail = '${mover.id} played "${result.uciMove}": $reason';
        return record(GameEnd(outcome: moverLoses, termination: GameTermination.illegalMove, detail: detail), detail);
      }
      moveStats.add(MoveStat(moveStopwatch.elapsedMilliseconds, result.depth, result.nodes, result.evaluation));
    }
  }
}
