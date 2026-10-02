import 'package:ace/chess_core/game_end.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_stats.dart';
import 'package:flutter_test/flutter_test.dart';

GameRecord _record({
  required bool aIsWhite,
  required GameOutcome outcome,
  GameTermination termination = GameTermination.checkmate,
  int bookPlies = 0,
  List<MoveStat> stats = const [],
}) {
  return GameRecord(
    gameNumber: 1,
    openingIndex: 0,
    startFen: 'start',
    bookPlies: bookPlies,
    whiteId: aIsWhite ? 'a' : 'b',
    blackId: aIsWhite ? 'b' : 'a',
    whiteName: aIsWhite ? 'A' : 'B',
    blackName: aIsWhite ? 'B' : 'A',
    engineAIsWhite: aIsWhite,
    end: GameEnd(outcome: outcome, termination: termination),
    uciMoves: const [],
    sanMoves: const [],
    moveStats: stats,
    duration: const Duration(seconds: 1),
  );
}

void main() {
  test('W/D/L and colour split are from A\'s point of view', () {
    final stats = MatchStats('A', 'B', const Duration(milliseconds: 100))
      ..add(_record(aIsWhite: true, outcome: GameOutcome.whiteWin)) // A wins as White
      ..add(_record(aIsWhite: false, outcome: GameOutcome.whiteWin)) // A loses as Black
      ..add(_record(aIsWhite: false, outcome: GameOutcome.blackWin)) // A wins as Black
      ..add(_record(aIsWhite: true, outcome: GameOutcome.draw, termination: GameTermination.stalemate));

    expect([stats.total.wins, stats.total.draws, stats.total.losses], [2, 1, 1]);
    expect([stats.aAsWhite.wins, stats.aAsWhite.draws, stats.aAsWhite.losses], [1, 1, 0]);
    expect([stats.aAsBlack.wins, stats.aAsBlack.draws, stats.aAsBlack.losses], [1, 0, 1]);
    expect(stats.terminations[GameTermination.checkmate], 3);
    expect(stats.terminations[GameTermination.stalemate], 1);
    expect(stats.gamesPlayed, 4);
  });

  test('search stats go to the right engine, allowing for book moves', () {
    // 1 book ply, so the first engine move is Black's. A is White.
    final stats = MatchStats('A', 'B', const Duration(milliseconds: 100))
      ..add(_record(aIsWhite: true, outcome: GameOutcome.draw, bookPlies: 1, stats: const [
        MoveStat(100, 4, 1000, 0), // Black = B
        MoveStat(200, 6, 3000, 0), // White = A (overrun)
        MoveStat(100, 4, 1000, 0), // Black = B
      ]));
    expect(stats.searchA.moves, 1);
    expect(stats.searchA.averageDepth, 6);
    expect(stats.searchA.overruns, 1);
    expect(stats.searchB.moves, 2);
    expect(stats.searchB.averageNodes, 1000);
  });

  test('forfeits are charged to the side that lost', () {
    final stats = MatchStats('A', 'B', const Duration(milliseconds: 100))
      ..add(_record(aIsWhite: true, outcome: GameOutcome.blackWin, termination: GameTermination.illegalMove))
      ..add(_record(aIsWhite: true, outcome: GameOutcome.whiteWin, termination: GameTermination.engineError));
    expect(stats.searchA.illegalMoves, 1);
    expect(stats.searchB.crashes, 1);
  });

  test('summary text and JSON', () {
    final stats = MatchStats('ACE v2', 'ACE v1', const Duration(milliseconds: 100))
      ..add(_record(aIsWhite: true, outcome: GameOutcome.whiteWin));
    expect(stats.toSummaryText(), contains('ACE v2 (A) vs ACE v1 (B)'));
    expect(stats.toJson()['games'], 1);
  });
}
