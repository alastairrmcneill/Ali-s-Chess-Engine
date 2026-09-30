// Plays a match between two engine versions and writes games.pgn, report.txt and summary.json.
//
//   dart run bin/match.dart --engine1 v2 --engine2 v1 --games 1000 --movetime 100
//
// Run `dart run bin/match.dart --help` for all options.
import 'dart:async';
import 'dart:io';

import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_runner.dart';
import 'package:ace/match/match_stats.dart';
import 'package:ace/match/match_storage.dart';
import 'package:ace/match/opening_book_data.dart';
import 'package:args/args.dart';

Future<void> main(List<String> arguments) async {
  ArgParser parser = ArgParser()
    ..addOption("engine1", abbr: "1", help: "First engine id", defaultsTo: latestEngineId)
    ..addOption("engine2", abbr: "2", help: "Second engine id", defaultsTo: latestEngineId)
    ..addOption("games", abbr: "g", help: "Number of games (rounded up to even)", defaultsTo: "1000")
    ..addOption("movetime", abbr: "t", help: "Thinking time per move in ms", defaultsTo: "100")
    ..addOption("movetime2", help: "Thinking time for engine 2 if different (handicap / sanity checks)")
    ..addOption("concurrency",
        abbr: "c",
        help: "Games played in parallel",
        defaultsTo: "${Platform.numberOfProcessors > 1 ? Platform.numberOfProcessors - 1 : 1}")
    ..addOption("max-plies", help: "Adjudicate a draw after this many plies", defaultsTo: "500")
    ..addOption("opening-offset", help: "First opening book line to use (0-${openingBook.length - 1})", defaultsTo: "0")
    ..addOption("out", abbr: "o", help: "Folder to save matches in", defaultsTo: "matches")
    ..addFlag("help", abbr: "h", negatable: false);

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln("${error.message}\n\n${parser.usage}");
    exit(64);
  }
  if (args["help"]) {
    stdout.writeln("Usage: dart run bin/match.dart [options]\n\n${parser.usage}");
    stdout.writeln("\nAvailable engines: ${engineRegistry.keys.join(", ")}");
    return;
  }

  MatchConfig config;
  try {
    config = MatchConfig(
      engine1Id: args["engine1"],
      engine2Id: args["engine2"],
      moveTimeMs: int.parse(args["movetime"]),
      engine2MoveTimeMs: args["movetime2"] == null ? null : int.parse(args["movetime2"]),
      games: int.parse(args["games"]),
      concurrency: int.parse(args["concurrency"]),
      maxPlies: int.parse(args["max-plies"]),
      openingOffset: int.parse(args["opening-offset"]),
    );
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    exit(64);
  }

  MatchRecorder recorder = await MatchRecorder.create(Directory(args["out"]), config);
  MatchRunner runner = MatchRunner(config);

  stdout.writeln("${config.engine1.label} vs ${config.engine2.label}: ${config.games} games, "
      "${config.concurrency} at a time");
  stdout.writeln("Saving to ${recorder.directory.path}  (Ctrl+C to stop early and still get a report)\n");

  // Ctrl+C stops the match but still writes the report for the games played so far
  StreamSubscription<ProcessSignal> interrupt = ProcessSignal.sigint.watch().listen((_) {
    stdout.writeln("\nStopping...");
    runner.stop();
  });

  Stopwatch stopwatch = Stopwatch()..start();
  List<Future<void>> pendingWrites = [];
  runner.events.listen(
    (event) {
      if (event is GameFinished) {
        pendingWrites.add(recorder.addGame(event.game));
        MatchStats stats = MatchStats.fromGames(runner.finishedGames, config.engine1.label, config.engine2.label);
        int done = runner.finishedGames.length;
        Duration elapsed = stopwatch.elapsed;
        Duration remaining = elapsed * ((config.games - done) / done);
        stdout.write("\r[$done/${config.games}] ${stats.summaryLine} | ${_duration(elapsed)} elapsed, "
            "~${_duration(remaining)} left   ");
      }
    },
    onError: (error) => stderr.writeln("\n$error"),
  );

  await runner.run();
  await interrupt.cancel();
  await Future.wait(pendingWrites);

  List<GameRecord> games = runner.finishedGames;
  await recorder.finish(games, complete: runner.isComplete);
  stdout.writeln("\n");
  stdout.writeln(await recorder.reportFile.readAsString());
  stdout.writeln("Saved games.pgn, report.txt and summary.json to ${recorder.directory.path}");
  exit(0);
}

String _duration(Duration duration) {
  int minutes = duration.inMinutes;
  int seconds = duration.inSeconds % 60;
  return minutes > 0 ? "${minutes}m${seconds.toString().padLeft(2, "0")}s" : "${seconds}s";
}
