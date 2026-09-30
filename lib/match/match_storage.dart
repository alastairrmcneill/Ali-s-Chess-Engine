import 'dart:convert';
import 'dart:io';

import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_runner.dart';
import 'package:ace/match/match_stats.dart';
import 'package:ace/match/pgn.dart';
import 'package:ace/match/report.dart';

/// Writes a match to its own folder as it runs:
///   games.pgn     every game, appended as soon as it finishes (so a stopped match keeps its games)
///   summary.json  config, stats and suspicious moves (read by the app's saved match list and the inspector)
///   report.txt    human readable report
class MatchRecorder {
  final Directory directory;
  final MatchConfig config;
  final DateTime startedAt;

  MatchRecorder._(this.directory, this.config, this.startedAt);

  File get pgnFile => File("${directory.path}/games.pgn");
  File get summaryFile => File("${directory.path}/summary.json");
  File get reportFile => File("${directory.path}/report.txt");

  static Future<MatchRecorder> create(Directory root, MatchConfig config) async {
    DateTime now = DateTime.now();
    String stamp = "${now.year}-${_two(now.month)}-${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}";
    String name = "${stamp}_${config.engine1.engineId}_vs_${config.engine2.engineId}";
    Directory directory = await Directory("${root.path}/$name").create(recursive: true);
    MatchRecorder recorder = MatchRecorder._(directory, config, now);
    await recorder.pgnFile.writeAsString("");
    return recorder;
  }

  String get _pgnDate => "${startedAt.year}.${_two(startedAt.month)}.${_two(startedAt.day)}";

  Future<void> _lastWrite = Future.value();

  /// Appends a finished game to games.pgn. Writes are queued so games finishing together can't interleave.
  Future<void> addGame(GameRecord game) {
    PgnGame pgn = game.toPgnGame(event: "${config.engine1.label} vs ${config.engine2.label}", date: _pgnDate);
    _lastWrite = _lastWrite.then((_) => pgnFile.writeAsString("${pgn.toPgn()}\n", mode: FileMode.append, flush: true));
    return _lastWrite;
  }

  /// Writes the summary and report. Call when the match finishes or is stopped.
  Future<MatchStats> finish(List<GameRecord> games, {required bool complete}) async {
    MatchStats stats = MatchStats.fromGames(games, config.engine1.label, config.engine2.label);
    List<SuspiciousMove> suspicious = suspiciousMoves(games);

    Map<String, dynamic> summary = {
      "format": 1,
      "startedAt": startedAt.toIso8601String(),
      "finishedAt": DateTime.now().toIso8601String(),
      "complete": complete,
      "config": config.toJson(),
      "stats": stats.toJson(),
      "summaryLine": stats.summaryLine,
      "suspiciousMoves": suspicious.take(500).map((move) => move.toJson()).toList(),
    };
    await summaryFile.writeAsString(const JsonEncoder.withIndent("  ").convert(summary));
    await reportFile.writeAsString(buildReport(
      stats: stats,
      games: games,
      engine1: config.engine1,
      engine2: config.engine2,
      complete: complete,
    ));
    return stats;
  }

  static String _two(int value) => value.toString().padLeft(2, "0");
}

/// A match folder written by [MatchRecorder]
class SavedMatch {
  final Directory directory;
  final Map<String, dynamic> summary;

  SavedMatch(this.directory, this.summary);

  MatchConfig get config => MatchConfig.fromJson(summary["config"]);
  String get summaryLine => summary["summaryLine"] ?? "";
  bool get complete => summary["complete"] ?? false;
  DateTime get startedAt => DateTime.tryParse(summary["startedAt"] ?? "") ?? DateTime(2000);
  List<SuspiciousMove> get suspiciousMoves =>
      (summary["suspiciousMoves"] as List? ?? []).map((json) => SuspiciousMove.fromJson(json)).toList();

  File get pgnFile => File("${directory.path}/games.pgn");
  File get reportFile => File("${directory.path}/report.txt");

  /// All games, sorted by game number
  Future<List<GameRecord>> loadGames() async {
    List<GameRecord> games =
        PgnGame.parseAll(await pgnFile.readAsString()).map((game) => GameRecord.fromPgnGame(game)).toList();
    games.sort((a, b) => a.gameNumber.compareTo(b.gameNumber));
    return games;
  }

  static Future<SavedMatch?> load(Directory directory) async {
    File summary = File("${directory.path}/summary.json");
    if (!await summary.exists()) return null;
    return SavedMatch(directory, jsonDecode(await summary.readAsString()));
  }

  /// Saved matches under [root], newest first
  static Future<List<SavedMatch>> list(Directory root) async {
    if (!await root.exists()) return [];
    List<SavedMatch> matches = [];
    await for (FileSystemEntity entity in root.list()) {
      if (entity is! Directory) continue;
      SavedMatch? match = await load(entity);
      if (match != null) matches.add(match);
    }
    matches.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return matches;
  }
}
