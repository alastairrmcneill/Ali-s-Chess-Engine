import 'dart:convert';
import 'dart:io';

import 'package:ace/chess_core/game_end.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/pgn_writer.dart';
import 'package:ace/match/thinking_log.dart';
import 'package:ace/match_manager/match_config.dart';
import 'package:ace/match_manager/match_stats.dart';

/// Writes a match's results folder: config.txt, games.pgn, thinking.jsonl (engines that report it), errors.log, summary.txt, summary.json.
class MatchOutput {
  final Directory directory;
  final MatchConfig config;
  final String event;

  MatchOutput._(this.directory, this.config, this.event);

  static MatchOutput create(MatchConfig config, {required String engineAName, required String engineBName}) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final directory = Directory('match_results/${stamp}_${config.engineAId}-vs-${config.engineBId}')
      ..createSync(recursive: true);
    return MatchOutput._(directory, config, '$engineAName vs $engineBName');
  }

  File get _pgn => File('${directory.path}/games.pgn');
  File get _thinking => File('${directory.path}/thinking.jsonl');
  File get _errors => File('${directory.path}/errors.log');

  void writeConfig({required int openingCount, required List<String> warnings}) {
    String? commit;
    try {
      final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
      if (result.exitCode == 0) commit = (result.stdout as String).trim();
    } catch (_) {}

    File('${directory.path}/config.txt').writeAsStringSync([
      'engine A:   ${config.engineAId}',
      'engine B:   ${config.engineBId}',
      'games:      ${config.games}',
      if (config.depth == null) 'movetime:   ${config.moveTime.inMilliseconds} ms' else 'depth:      ${config.depth} (fixed, untimed)',
      'max moves:  ${config.maxMoves} per side (engine moves only)',
      'openings:   $openingCount (lib/match/opening_book_data.dart)',
      'git commit: ${commit ?? 'unknown'}',
      'started:    ${DateTime.now().toIso8601String()}',
      if (warnings.isNotEmpty) ...['', 'warnings:', ...warnings.map((w) => '  $w')],
      '',
    ].join('\n'));
  }

  /// Appends the game straight away, so nothing is lost if the match is stopped.
  void addGame(GameRecord record) {
    _pgn.writeAsStringSync('${PgnWriter.gameToPgn(record, event: event, moveTime: config.moveTime)}\n',
        mode: FileMode.append);

    final thinking = ThinkingLog.linesForGame(record);
    if (thinking.isNotEmpty) {
      _thinking.writeAsStringSync('${thinking.join('\n')}\n', mode: FileMode.append);
    }

    final forfeit =
        record.end.termination == GameTermination.illegalMove || record.end.termination == GameTermination.engineError;
    if (forfeit) {
      _errors.writeAsStringSync(
        [
          '=== Game ${record.gameNumber}: ${record.whiteId} (White) vs ${record.blackId} (Black) ===',
          'result:    ${record.end}',
          'opening:   book #${record.openingIndex + 1}',
          'reproduce: position fen ${record.startFen} moves ${record.uciMoves.join(' ')}',
          if (record.errorDetail != null) record.errorDetail!,
          '',
          '',
        ].join('\n'),
        mode: FileMode.append,
      );
    }
  }

  void writeSummary(MatchStats stats) {
    File('${directory.path}/summary.txt')
        .writeAsStringSync(stats.toSummaryText(openingsDescription: 'opening_book_data.dart'));
  }

  void writeSummaryJson(MatchStats stats) {
    File('${directory.path}/summary.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(stats.toJson()));
  }
}
