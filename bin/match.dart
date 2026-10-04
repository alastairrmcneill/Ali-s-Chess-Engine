import 'dart:async';
import 'dart:io';

import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match/opening_book.dart';
import 'package:ace/match_manager/match_config.dart';
import 'package:ace/match_manager/match_runner.dart';
import 'package:ace/chess_core/game_end.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match_manager/match_stats.dart';
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
    );
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    _usage(parser, 64);
  } on ArgumentError catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    _usage(parser, 64);
  }

  final book = OpeningBook.standard();
  for (final warning in book.warnings) {
    stderr.writeln('Opening book: $warning');
  }

  final engineA = EngineRegistry.create(config.engineAId);
  final engineB = EngineRegistry.create(config.engineBId);
  final runner = MatchRunner(config);

  stdout.writeln('${engineA.displayName} (A) vs ${engineB.displayName} (B): ${config.games} games, '
      '${config.moveTime.inMilliseconds} ms/move, ${book.openings.length} openings');
  stdout.writeln('Writing results to match_results/\n');

  final stats = await runner.runMatch(
    engineA: engineA,
    engineB: engineB,
    engineAName: engineA.displayName,
    engineBName: engineB.displayName,
    openingBookWarnings: book.warnings,
    onGameFinished: (record, stats) => stdout.writeln(_progressLine(record, stats, config.games)),
  );

  stdout.writeln('\n${stats.toSummaryText(openingsDescription: 'opening_book_data.dart')}');
  exit(0);
}

Never _usage(ArgParser parser, int code) {
  (code == 0 ? stdout : stderr)
      .writeln('Usage: dart run bin/match.dart --a <engine> --b <engine> [options]\n\n${parser.usage}');
  exit(code);
}

/// e.g. `[  12/1000] A (white) won by checkmate in 41 moves | A +5 =3 -4 (54.2%)`
String _progressLine(GameRecord record, MatchStats stats, int totalGames) {
  final width = totalGames.toString().length;
  final result = switch (record.end.outcome) {
    GameOutcome.draw => 'draw',
    _ => (record.end.outcome == GameOutcome.whiteWin) == record.engineAIsWhite ? 'A won' : 'B won',
  };
  final colour = record.engineAIsWhite ? 'A white' : 'A black';
  final how = record.end.termination.name;
  final score = (stats.total.score * 100).toStringAsFixed(1);
  return '[${record.gameNumber.toString().padLeft(width)}/$totalGames] $colour: $result by $how '
      '(${(record.uciMoves.length / 2).ceil()} moves) | A ${stats.total} ($score%)';
}
