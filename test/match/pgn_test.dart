import 'package:ace/match/game_record.dart';
import 'package:ace/match/pgn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("parses headers, comments, NAGs and skips variations", () {
    List<PgnGame> games = PgnGame.parseAll('''
[Event "Test"]
[Result "1-0"]

1. e4 {best by test} e5 2. Nf3 \$1 (2. Qh5 Nc6 (2... g6) 3. Bc4) 2... Nc6 ; a line comment
3. Bb5 1-0

[Event "Second"]

1.d4 d5 *
''');

    expect(games.length, 2);
    expect(games[0].headers["Event"], "Test");
    expect(games[0].moves.map((move) => move.san), ["e4", "e5", "Nf3", "Nc6", "Bb5"]);
    expect(games[0].moves[0].comment, "best by test");
    expect(games[0].moves[2].nags, [1]);
    expect(games[0].result, "1-0");
    expect(games[1].moves.map((move) => move.san), ["d4", "d5"]);
    expect(games[1].result, "*");
  });

  test("a game record survives a round trip through PGN", () {
    GameRecord original = GameRecord(
      gameNumber: 7,
      openingIndex: 3,
      white: const MatchPlayer(engineId: "v2", moveTimeMs: 100, label: "ACE v2"),
      black: const MatchPlayer(engineId: "v1", moveTimeMs: 100, label: "ACE v1"),
      moves: [
        MoveRecord(uci: "e2e4", san: "e4", book: true),
        MoveRecord(uci: "e7e5", san: "e5", book: true),
        MoveRecord(
            uci: "g1f3", san: "Nf3", scoreCp: 45, depth: 7, nodes: 41230, timeMs: 98, pvSan: ["Nf3", "Nc6", "Bb5"]),
        MoveRecord(uci: "b8c6", san: "Nc6", scoreCp: -120, depth: 6, nodes: 12, timeMs: 101, suspicion: "eval fell"),
        MoveRecord(uci: "f1b5", san: "Bb5", mateIn: 3, depth: 5, timeMs: 99),
      ],
      result: "0-1",
      termination: Termination.illegalMove,
      terminationDetail: "ACE v2 played e1e3",
    );

    String pgn = original.toPgnGame(date: "2026.01.01").toPgn();
    expect(pgn, contains("{+0.45/7 98ms 41230 nodes; pv: Nf3 Nc6 Bb5}"));
    expect(pgn, contains("Nc6 \$2"));

    GameRecord parsed = GameRecord.fromPgnGame(PgnGame.parseAll(pgn).single);
    expect(parsed.toJson(), original.toJson());
  });
}
