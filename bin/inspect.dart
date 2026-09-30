// Shows an engine's top moves in a position, to understand why it played what it did.
//
//   dart run bin/inspect.dart --engine v1 --fen "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
//   dart run bin/inspect.dart --engine v1 --pgn matches/<match>/games.pgn --game 12 --ply 34
//
// Run `dart run bin/inspect.dart --help` for all options.
import 'dart:io';

import 'package:ace/analysis/position_inspector.dart';
import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/fen.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/uci.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/pgn.dart';
import 'package:args/args.dart';

Future<void> main(List<String> arguments) async {
  ArgParser parser = ArgParser()
    ..addOption("engine", abbr: "e", help: "Engine id to analyse with", defaultsTo: latestEngineId)
    ..addOption("fen", abbr: "f", help: "Position to analyse (defaults to the starting position)")
    ..addOption("moves", abbr: "m", help: "UCI moves to play from --fen first, e.g. \"e2e4 e7e5\"")
    ..addOption("pgn", help: "games.pgn from a match, used with --game and --ply")
    ..addOption("game", help: "Game number (Round) in --pgn")
    ..addOption("ply", help: "1-based ply in the game: analyses the position before this move (report.txt lists it)")
    ..addOption("top", abbr: "n", help: "How many moves to show", defaultsTo: "5")
    ..addOption("movetime", abbr: "t", help: "Thinking time per candidate move in ms", defaultsTo: "300")
    ..addFlag("help", abbr: "h", negatable: false);

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln("${error.message}\n\n${parser.usage}");
    exit(64);
  }
  if (args["help"]) {
    stdout.writeln("Usage: dart run bin/inspect.dart [options]\n\n${parser.usage}");
    stdout.writeln("\nAvailable engines: ${engineRegistry.keys.join(", ")}");
    return;
  }

  String startFen = args["fen"] ?? FenPosition.startingFen;
  List<String> moves = (args["moves"] as String?)?.split(" ").where((move) => move.isNotEmpty).toList() ?? [];
  MoveRecord? playedMove;
  String? playedBy;

  if (args["pgn"] != null) {
    if (args["game"] == null || args["ply"] == null) {
      stderr.writeln("--pgn needs --game and --ply");
      exit(64);
    }
    int gameNumber = int.parse(args["game"]);
    int ply = int.parse(args["ply"]);
    GameRecord? game = PgnGame.parseAll(File(args["pgn"]).readAsStringSync())
        .map((pgn) => GameRecord.fromPgnGame(pgn))
        .where((game) => game.gameNumber == gameNumber)
        .firstOrNull;
    if (game == null) {
      stderr.writeln("Game $gameNumber not found in ${args["pgn"]}");
      exit(1);
    }
    if (ply < 1 || ply > game.moves.length) {
      stderr.writeln("Game $gameNumber has ${game.moves.length} plies");
      exit(1);
    }
    startFen = game.startFen;
    moves = game.moves.take(ply - 1).map((move) => move.uci).toList();
    playedMove = game.moves[ply - 1];
    playedBy = game.moverAt(ply - 1).label;
  }

  if (!engineRegistry.containsKey(args["engine"])) {
    stderr.writeln("Unknown engine '${args["engine"]}'. Available: ${engineRegistry.keys.join(", ")}");
    exit(64);
  }
  int moveTime = int.parse(args["movetime"]);
  int top = int.parse(args["top"]);

  // Replay the moves to show the position being analysed
  Board board = Board.fromFen(startFen);
  for (String uci in moves) {
    Move? move = Uci.toLegalMove(board, uci);
    if (move == null) {
      stderr.writeln("Illegal move $uci");
      exit(64);
    }
    board.makeMove(move);
  }
  String fen = board.toFen();
  stdout.writeln("Position (${fen.split(" ")[1] == "w" ? "white" : "black"} to move): $fen");
  if (playedMove != null) {
    stdout.writeln("Played in the game by $playedBy: ${playedMove.san}  {${playedMove.comment}}");
  }

  List<CandidateMove> candidates = await PositionInspector.analyse(
    engineId: args["engine"],
    startFen: startFen,
    uciMoves: moves,
    msPerCandidate: moveTime,
    onProgress: (done, total) => stdout.write("\rAnalysing with ${args["engine"]}: $done/$total moves "
        "(${moveTime}ms each)"),
  );
  stdout.writeln("\n");

  for (int i = 0; i < candidates.length && i < top; i++) {
    CandidateMove candidate = candidates[i];
    String marker = playedMove != null && candidate.uci == playedMove.uci ? "  <- played" : "";
    stdout.writeln("${"${i + 1}.".padRight(4)}${candidate.san.padRight(8)}${candidate.scoreText.padRight(9)}"
        "depth ${candidate.depth ?? "-"}  ${candidate.note ?? candidate.lineSan.join(" ")}$marker");
  }
  if (playedMove != null) {
    int rank = candidates.indexWhere((candidate) => candidate.uci == playedMove!.uci);
    if (rank >= top) {
      CandidateMove played = candidates[rank];
      stdout.writeln("...\n${"${rank + 1}.".padRight(4)}${played.san.padRight(8)}${played.scoreText.padRight(9)}"
          "depth ${played.depth ?? "-"}  ${played.lineSan.join(" ")}  <- played");
    }
  }
  stdout.writeln("\nScores are from the moving side's point of view.");
}
