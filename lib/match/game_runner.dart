import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/opening_book.dart';

class GameRunner {
  Future<GameRecord> playGame({
    required int gameNumber,
    required Opening opening,
    required ChessEngine white,
    required ChessEngine black,
    required bool engineAIsWhite,
    required SearchLimits searchLimits,
    required int maxPlies,
  }) async {
    final fen = FenPosition.startingPosition;
    final referee = Referee(
      fen,
      maxPlies: opening.moves.length + maxPlies,
    );
    final stopwatch = Stopwatch()..start();
    final moveStats = <MoveStat>[];

    for (final move in opening.moves) {
      final reason = referee.tryPlayUci(move);
      if (reason != null) throw Exception('Invalid opening move: $move, reason: $reason');
    }

    white.newGame();
    black.newGame();

    GameRecord record(GameEnd end, [String? errorDetail]) => GameRecord(
          gameNumber: gameNumber,
          openingIndex: opening.index,
          startFen: fen,
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

      final sw = Stopwatch()..start();
      EngineMoveResult result;

      try {
        result = mover.getMove(
          fen,
          referee.uciHistory,
          searchLimits,
        );
      } catch (e) {
        return record(
          GameEnd(outcome: moverLoses, termination: GameTermination.engineError, detail: e.toString()),
          e.toString(),
        );
      }
      sw.stop();

      final reason = referee.tryPlayUci(result.uciMove);
      if (reason != null) {
        return record(
          GameEnd(outcome: moverLoses, termination: GameTermination.illegalMove, detail: reason),
          reason,
        );
      }
      moveStats.add(
        MoveStat(
          sw.elapsedMilliseconds,
          result.depth,
          result.nodes,
          result.evaluation,
          pv: result.principalVariation,
        ),
      );
    }
  }
}
