import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_stats.dart';
import 'package:ace/match/report.dart';
import 'package:flutter_test/flutter_test.dart';

const MatchPlayer a = MatchPlayer(engineId: "v1", moveTimeMs: 100, label: "A");
const MatchPlayer b = MatchPlayer(engineId: "v1", moveTimeMs: 100, label: "B");

GameRecord game(int number, String result, {List<MoveRecord>? moves, Termination? termination}) {
  bool aIsWhite = number.isOdd;
  return GameRecord(
    gameNumber: number,
    openingIndex: (number - 1) ~/ 2,
    white: aIsWhite ? a : b,
    black: aIsWhite ? b : a,
    moves: moves ?? [],
    result: result,
    termination: termination ?? (result == "1/2-1/2" ? Termination.repetition : Termination.checkmate),
  );
}

void main() {
  test("Elo from score matches known values", () {
    expect(MatchStats.eloFromScore(0.5), 0);
    expect(MatchStats.eloFromScore(0.55), closeTo(34.86, 0.01));
    expect(MatchStats.eloFromScore(0.75), closeTo(190.85, 0.01));
    expect(MatchStats.eloFromScore(0.25), closeTo(-190.85, 0.01));
    expect(MatchStats.erf(1), closeTo(0.8427, 0.0001));
  });

  test("counts results from engine 1's point of view across colours", () {
    // A wins as white (game 1), A wins as black (game 2), draw, A loses as black
    List<GameRecord> games = [game(1, "1-0"), game(2, "0-1"), game(3, "1/2-1/2"), game(4, "1-0")];
    MatchStats stats = MatchStats.fromGames(games, "A", "B");
    expect([stats.wins, stats.draws, stats.losses], [2, 1, 1]);
    expect(stats.score, 0.625);
    expect(stats.terminations[Termination.checkmate], 3);
    expect(stats.los, closeTo(0.718, 0.001)); // 0.5 * (1 + erf(1 / sqrt(6)))
  });

  test("error margin shrinks with more games and is null when there is no spread", () {
    List<GameRecord> few = [for (int i = 1; i <= 8; i++) game(i, i % 4 == 1 ? "1-0" : "1/2-1/2")];
    List<GameRecord> many = [for (int i = 1; i <= 200; i++) game(i, i % 4 == 1 ? "1-0" : "1/2-1/2")];
    double fewError = MatchStats.fromGames(few, "A", "B").eloError95!;
    double manyError = MatchStats.fromGames(many, "A", "B").eloError95!;
    expect(manyError, lessThan(fewError));

    List<GameRecord> allDraws = [for (int i = 1; i <= 10; i++) game(i, "1/2-1/2")];
    expect(MatchStats.fromGames(allDraws, "A", "B").eloError95, isNull);
  });

  test("flags a move when the mover's win chance collapses by its next turn", () {
    List<MoveRecord> moves = [
      MoveRecord(uci: "e2e4", san: "e4", scoreCp: 30),
      MoveRecord(uci: "e7e5", san: "e5", scoreCp: 0),
      MoveRecord(uci: "d1h5", san: "Qh5", scoreCp: 40), // White thinks it is fine...
      MoveRecord(uci: "b8c6", san: "Nc6", scoreCp: 10),
      MoveRecord(uci: "f1c4", san: "Bc4", scoreCp: -400), // ...but a move later it is losing
      MoveRecord(uci: "g8f6", san: "Nf6", scoreCp: 1700), // Black: +17 falling to +8 is still winning, not flagged
      MoveRecord(uci: "h5f7", san: "Qxf7+", scoreCp: -1400), // White: already lost, -4 to -14 is only 18 points
      MoveRecord(uci: "e8f7", san: "Kxf7", scoreCp: 800),
      MoveRecord(uci: "a2a3", san: "a3", scoreCp: -900),
    ];
    GameRecord record = game(1, "1-0", moves: moves, termination: Termination.illegalMove);
    flagSuspiciousMoves(record);

    expect(record.moves[2].suspicion, contains("eval fell from +0.40 to -4.00"));
    expect(record.moves[5].suspicion, isNull);
    expect(record.moves.where((move) => move.suspicion != null).length, 1);
  });
}
