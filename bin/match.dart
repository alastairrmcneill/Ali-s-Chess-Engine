import 'dart:async';
import 'dart:io';

import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_config.dart';
import 'package:ace/match/match_output.dart';
import 'package:ace/match/match_runner.dart';
import 'package:ace/match/match_stats.dart';
import 'package:ace/match/opening_book.dart';
import 'package:args/args.dart';

/// dart run bin/match.dart --a v2 --b v1 [--games 1000] [--movetime 100] [--max-moves 300] [--out match_results]
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('a', help: 'Engine A id (the one being tested)')
    ..addOption('b', help: 'Engine B id (the baseline)')
    ..addOption('games', defaultsTo: '1000', help: 'Number of games (even)')
    ..addOption('movetime', defaultsTo: '100', help: 'Thinking time per move, ms')
    ..addOption('max-moves', defaultsTo: '300', help: 'Engine moves per side before a draw is declared')
    ..addOption('out', defaultsTo: 'match_results', help: 'Folder for results')
    ..addFlag('list', negatable: false, help: 'List engine ids and exit')
    ..addFlag('quiet', negatable: false, help: 'Only print the final summary')
    ..addFlag('help', abbr: 'h', negatable: false);

  late final ArgResults args;
  late final MatchConfig config;
  try {
    args = parser.parse(arguments);
    if (args['help'] as bool) _usage(parser, 0);
    if (args['list'] as bool) {
      stdout.writeln(EngineRegistry.allIds.join('\n'));
      exit(0);
    }
    final a = args['a'] as String?, b = args['b'] as String?;
    if (a == null || b == null) throw const FormatException('--a and --b are required');
    for (final id in [a, b]) {
      if (!EngineRegistry.allIds.contains(id)) {
        throw FormatException('Unknown engine "$id". Known: ${EngineRegistry.allIds.join(', ')}');
      }
    }
    config = MatchConfig(
      engineAId: a,
      engineBId: b,
      games: int.parse(args['games'] as String),
      moveTime: Duration(milliseconds: int.parse(args['movetime'] as String)),
      maxMoves: int.parse(args['max-moves'] as String),
      outDir: args['out'] as String,
    );
    config.validate();
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    _usage(parser, 64);
  } on ArgumentError catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    _usage(parser, 64);
  }
  final quiet = args['quiet'] as bool;

  final book = OpeningBook.standard();
  for (final warning in book.warnings) {
    stderr.writeln('Opening book: $warning');
  }

  final engineA = EngineRegistry.create(config.engineAId);
  final engineB = EngineRegistry.create(config.engineBId);
  final output = MatchOutput.create(config, engineAName: engineA.displayName, engineBName: engineB.displayName);

  // First Ctrl-C: finish the current game, then stop and write the summary. Second Ctrl-C: quit now.
  var stopRequested = false;
  final sigint = ProcessSignal.sigint.watch().listen((_) {
    if (stopRequested) exit(130);
    stopRequested = true;
    stderr.writeln('\nStopping after this game… (Ctrl-C again to quit immediately)');
  });

  final runner = MatchRunner(
    config,
    shouldStop: () => stopRequested,
    onGameFinished: (GameRecord record, MatchStats stats) {
      output.addGame(record);
      if (stats.gamesPlayed % 50 == 0) output.writeSummary(stats);
      if (!quiet) stdout.writeln(_progressLine(record, stats, config));
      if (!quiet && record.errorDetail != null) stderr.writeln('  ! ${record.end.detail}');
    },
  );

  stdout.writeln('${engineA.displayName} (A) vs ${engineB.displayName} (B): ${config.games} games, '
      '${config.moveTime.inMilliseconds} ms/move, ${book.openings.length} openings');
  stdout.writeln('Writing results to ${output.directory.path}\n');

  final stats = await runner.run(book: book, engineA: engineA, engineB: engineB);
  output.writeConfig(openingCount: book.openings.length, warnings: [...book.warnings, ...runner.warnings]);
  output.writeSummary(stats);
  output.writeSummaryJson(stats);
  await sigint.cancel();

  stdout.writeln('\n${stats.toSummaryText(openingsDescription: 'opening_book_data.dart')}');
  stdout.writeln('Results: ${output.directory.path}');
  exit(0);
}

String _progressLine(GameRecord record, MatchStats stats, MatchConfig config) {
  final elo = stats.elo;
  final averageGame = stats.totalTime ~/ stats.gamesPlayed;
  final eta = averageGame * (config.games - stats.gamesPlayed);
  final width = '${config.games}'.length;
  return '[${'${stats.gamesPlayed}'.padLeft(width)}/${config.games}] '
      '${record.whiteId}-${record.blackId} ${record.end.pgnResult.padRight(7)} ${record.end.termination.name} '
      '(${record.uciMoves.length} ply, ${(record.duration.inMilliseconds / 1000).toStringAsFixed(1)}s) | '
      'A ${stats.total} | Elo ${MatchStats.formatElo(elo.elo)} ± ${elo.errorMargin.isFinite ? elo.errorMargin.toStringAsFixed(0) : '∞'} | '
      'ETA ${MatchStats.formatDuration(eta)}';
}

Never _usage(ArgParser parser, int code) {
  (code == 0 ? stdout : stderr).writeln('Usage: dart run bin/match.dart --a <engine> --b <engine> [options]\n\n${parser.usage}');
  exit(code);
}

