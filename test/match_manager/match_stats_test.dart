import 'package:ace/chess_core/game_end.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match_manager/match_stats.dart';
import 'package:flutter_test/flutter_test.dart';

GameRecord _record({
  required bool engineAIsWhite,
  required GameEnd end,
  int bookPlies = 0,
  List<MoveStat> moveStats = const [],
  Duration duration = Duration.zero,
}) =>
    GameRecord(
      gameNumber: 1,
      openingIndex: 0,
      startFen: 'startpos',
      bookPlies: bookPlies,
      whiteId: 'w',
      blackId: 'b',
      whiteName: 'White engine',
      blackName: 'Black engine',
      engineAIsWhite: engineAIsWhite,
      end: end,
      uciMoves: const [],
      sanMoves: const [],
      moveStats: moveStats,
      duration: duration,
    );

void main() {
  test('aggregates W/D/L, colour splits, terminations and per-engine search stats', () {
    final stats = MatchStats('Engine A', 'Engine B', const Duration(milliseconds: 100));

    // Game 1: A (White) wins by checkmate. Ply 0 is White (A), ply 1 is Black (B).
    stats.add(_record(
      engineAIsWhite: true,
      end: const GameEnd(outcome: GameOutcome.whiteWin, termination: GameTermination.checkmate),
      moveStats: const [MoveStat(50, 5, 1000, 20), MoveStat(60, 6, 1200, -10)],
    ));

    expect(stats.total.wins, 1);
    expect(stats.total.draws, 0);
    expect(stats.total.losses, 0);
    expect(stats.aAsWhite.wins, 1);
    expect(stats.aAsBlack.games, 0);
    expect(stats.terminations[GameTermination.checkmate], 1);
    expect(stats.searchA.moves, 1);
    expect(stats.searchA.totalTimeMs, 50);
    expect(stats.searchA.averageDepth, 5);
    expect(stats.searchA.averageNodes, 1000);
    expect(stats.searchB.moves, 1);
    expect(stats.searchB.totalTimeMs, 60);
    expect(stats.searchB.averageDepth, 6);
    expect(stats.searchB.averageNodes, 1200);

    // Game 2: A plays Black and wins (B, as White, is checkmated). Ply 0 is White (B), ply 1 is Black (A).
    stats.add(_record(
      engineAIsWhite: false,
      end: const GameEnd(outcome: GameOutcome.blackWin, termination: GameTermination.checkmate),
      moveStats: const [MoveStat(70, 4, 800, 5), MoveStat(80, 5, 900, -5)],
    ));

    expect(stats.total.wins, 2);
    expect(stats.aAsBlack.wins, 1);
    expect(stats.terminations[GameTermination.checkmate], 2);
    // searchA now has 2 moves (50 from game 1, 80 from game 2); searchB has 2 (60, 70).
    expect(stats.searchA.moves, 2);
    expect(stats.searchA.totalTimeMs, 130);
    expect(stats.searchB.moves, 2);
    expect(stats.searchB.totalTimeMs, 130);

    // Game 3: a draw by the fifty-move rule, A as White.
    stats.add(_record(
      engineAIsWhite: true,
      end: const GameEnd(outcome: GameOutcome.draw, termination: GameTermination.fiftyMoveRule),
    ));

    expect(stats.total.draws, 1);
    expect(stats.aAsWhite.draws, 1);
    expect(stats.terminations[GameTermination.fiftyMoveRule], 1);

    // Game 4: A (White) plays an illegal move and loses.
    stats.add(_record(
      engineAIsWhite: true,
      end: const GameEnd(outcome: GameOutcome.blackWin, termination: GameTermination.illegalMove, detail: 'oops'),
    ));

    expect(stats.total.losses, 1);
    expect(stats.aAsWhite.losses, 1);
    expect(stats.searchA.illegalMoves, 1);
    expect(stats.searchB.illegalMoves, 0);

    // Game 5: B (Black) crashes and A (White) wins.
    stats.add(_record(
      engineAIsWhite: true,
      end: const GameEnd(outcome: GameOutcome.whiteWin, termination: GameTermination.engineError, detail: 'boom'),
    ));

    expect(stats.total.wins, 3);
    expect(stats.searchB.crashes, 1);
    expect(stats.searchA.crashes, 0);

    expect(stats.gamesPlayed, 5);
  });

  test('flags moves that overran the configured move time', () {
    final stats = MatchStats('Engine A', 'Engine B', const Duration(milliseconds: 100));

    stats.add(_record(
      engineAIsWhite: true,
      end: const GameEnd(outcome: GameOutcome.draw, termination: GameTermination.maxMoves),
      moveStats: const [
        MoveStat(140, null, null, null), // within 100ms + 50ms grace, no overrun
        MoveStat(200, null, null, null), // over the grace period, an overrun
      ],
    ));

    expect(stats.searchA.overruns, 0);
    expect(stats.searchB.overruns, 1);
  });

  test('bookPlies shifts which search bucket a move belongs to', () {
    final stats = MatchStats('Engine A', 'Engine B', const Duration(milliseconds: 100));

    // bookPlies: 1 (odd), so engine move 0 is actually Black's move, not White's.
    stats.add(_record(
      engineAIsWhite: true, // A is White
      bookPlies: 1,
      end: const GameEnd(outcome: GameOutcome.draw, termination: GameTermination.maxMoves),
      moveStats: const [MoveStat(10, null, null, null)],
    ));

    // The lone engine move was Black's (B's), not White's (A's).
    expect(stats.searchA.moves, 0);
    expect(stats.searchB.moves, 1);
  });

  test('toSummaryText and toJson run without throwing and reflect the engines and totals', () {
    final stats = MatchStats('Engine A', 'Engine B', const Duration(milliseconds: 100));
    stats.add(_record(
      engineAIsWhite: true,
      end: const GameEnd(outcome: GameOutcome.whiteWin, termination: GameTermination.checkmate),
    ));

    final summary = stats.toSummaryText();
    expect(summary, contains('Engine A'));
    expect(summary, contains('Engine B'));

    final json = stats.toJson();
    expect(json['games'], 1);
    expect(json['total'], {'wins': 1, 'draws': 0, 'losses': 0});
  });
}
