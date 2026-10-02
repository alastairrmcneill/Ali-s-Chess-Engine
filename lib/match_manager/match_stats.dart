import 'package:ace/chess_core/game_end.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match_manager/elo.dart';

class WinDrawLoss {
  int wins = 0, draws = 0, losses = 0;

  int get games => wins + draws + losses;
  double get score => games == 0 ? 0 : (wins + 0.5 * draws) / games;

  @override
  String toString() => '+$wins =$draws -$losses';
}

/// Search stats for one engine role ('A' or 'B'). Keyed by role, not id, so v1-vs-v1 works.
class EngineSearchStats {
  int moves = 0, totalTimeMs = 0, maxTimeMs = 0;
  int depthSum = 0, depthCount = 0;
  int nodesSum = 0, nodesCount = 0;
  int overruns = 0; // moves that took longer than movetime + 50ms
  int illegalMoves = 0, crashes = 0;

  double get averageDepth => depthCount == 0 ? 0 : depthSum / depthCount;
  double get averageNodes => nodesCount == 0 ? 0 : nodesSum / nodesCount;
  double get averageTimeMs => moves == 0 ? 0 : totalTimeMs / moves;

  Map<String, dynamic> toJson() => {
        'moves': moves,
        'averageTimeMs': averageTimeMs,
        'maxTimeMs': maxTimeMs,
        'averageDepth': averageDepth,
        'averageNodes': averageNodes,
        'overruns': overruns,
        'illegalMoves': illegalMoves,
        'crashes': crashes,
      };
}

class MatchStats {
  final String engineAName, engineBName;
  final Duration moveTime;

  /// All from engine A's point of view.
  final WinDrawLoss total = WinDrawLoss(), aAsWhite = WinDrawLoss(), aAsBlack = WinDrawLoss();
  final Map<GameTermination, int> terminations = {};
  final EngineSearchStats searchA = EngineSearchStats(), searchB = EngineSearchStats();
  Duration totalTime = Duration.zero;

  MatchStats(this.engineAName, this.engineBName, this.moveTime);

  int get gamesPlayed => total.games;
  EloResult get elo => Elo.calculate(total.wins, total.draws, total.losses);

  void add(GameRecord record) {
    final colourStats = record.engineAIsWhite ? aAsWhite : aAsBlack;
    final aWon = record.end.outcome == (record.engineAIsWhite ? GameOutcome.whiteWin : GameOutcome.blackWin);
    for (final stats in [total, colourStats]) {
      if (record.end.outcome == GameOutcome.draw) {
        stats.draws++;
      } else if (aWon) {
        stats.wins++;
      } else {
        stats.losses++;
      }
    }

    terminations.update(record.end.termination, (n) => n + 1, ifAbsent: () => 1);
    totalTime += record.duration;

    for (int i = 0; i < record.moveStats.length; i++) {
      final stat = record.moveStats[i];
      final search = record.engineMoveIsWhite(i) == record.engineAIsWhite ? searchA : searchB;
      search.moves++;
      search.totalTimeMs += stat.timeMs;
      if (stat.timeMs > search.maxTimeMs) search.maxTimeMs = stat.timeMs;
      if (stat.timeMs > moveTime.inMilliseconds + 50) search.overruns++;
      if (stat.depth != null) {
        search.depthSum += stat.depth!;
        search.depthCount++;
      }
      if (stat.nodes != null) {
        search.nodesSum += stat.nodes!;
        search.nodesCount++;
      }
    }

    // The loser of a forfeit is the side that was to move.
    if (record.end.termination == GameTermination.illegalMove ||
        record.end.termination == GameTermination.engineError) {
      final loserIsWhite = record.end.outcome == GameOutcome.blackWin;
      final loser = loserIsWhite == record.engineAIsWhite ? searchA : searchB;
      if (record.end.termination == GameTermination.illegalMove) {
        loser.illegalMoves++;
      } else {
        loser.crashes++;
      }
    }
  }

  String toSummaryText({String? openingsDescription}) {
    final e = elo;
    final buffer = StringBuffer()
      ..writeln('$engineAName (A) vs $engineBName (B): $gamesPlayed games, ${moveTime.inMilliseconds} ms/move'
          '${openingsDescription == null ? '' : ', openings: $openingsDescription'}')
      ..writeln()
      ..writeln('Result (A\'s view):   $total    score ${_percent(total.score)}')
      ..writeln('Elo difference:      ${formatElo(e.elo)} ± ${_formatMargin(e.errorMargin)}  (95%)     '
          'LOS: ${_percent(e.likelihoodOfSuperiority)}')
      ..writeln()
      ..writeln('                 W     D     L    score')
      ..writeln(_colourRow('A as White', aAsWhite))
      ..writeln(_colourRow('A as Black', aAsBlack))
      ..writeln()
      ..writeln(
          'Terminations: ${GameTermination.values.where(terminations.containsKey).map((t) => '${t.name} ${terminations[t]}').join(', ')}')
      ..writeln()
      ..writeln('Search          avg depth   avg nodes   avg ms   max ms   overruns   illegal   crashes')
      ..writeln(_searchRow('A $engineAName', searchA))
      ..writeln(_searchRow('B $engineBName', searchB))
      ..writeln()
      ..writeln('Total time: ${formatDuration(totalTime)}');
    return buffer.toString();
  }

  Map<String, dynamic> toJson() {
    final e = elo;
    Map<String, int> wdl(WinDrawLoss x) => {'wins': x.wins, 'draws': x.draws, 'losses': x.losses};
    return {
      'engineA': engineAName,
      'engineB': engineBName,
      'moveTimeMs': moveTime.inMilliseconds,
      'games': gamesPlayed,
      'total': wdl(total),
      'aAsWhite': wdl(aAsWhite),
      'aAsBlack': wdl(aAsBlack),
      'score': e.score,
      'elo': e.elo.isFinite ? e.elo : null,
      'eloErrorMargin': e.errorMargin.isFinite ? e.errorMargin : null,
      'likelihoodOfSuperiority': e.likelihoodOfSuperiority,
      'terminations': {for (final t in terminations.keys) t.name: terminations[t]},
      'searchA': searchA.toJson(),
      'searchB': searchB.toJson(),
      'totalTimeSeconds': totalTime.inSeconds,
    };
  }

  static String formatElo(double elo) {
    if (elo == double.infinity) return '>+999';
    if (elo == double.negativeInfinity) return '<-999';
    return '${elo >= 0 ? '+' : ''}${elo.toStringAsFixed(1)}';
  }

  static String _formatMargin(double margin) => margin.isFinite ? margin.toStringAsFixed(1) : '∞';

  static String formatDuration(Duration d) =>
      d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m ${d.inSeconds % 60}s';

  static String _percent(double x) => '${(x * 100).toStringAsFixed(1)}%';

  static String _colourRow(String label, WinDrawLoss x) =>
      '${label.padRight(12)}${'${x.wins}'.padLeft(6)}${'${x.draws}'.padLeft(6)}${'${x.losses}'.padLeft(6)}'
      '${_percent(x.score).padLeft(9)}';

  static String _searchRow(String label, EngineSearchStats s) =>
      '${label.padRight(16)}${s.averageDepth.toStringAsFixed(1).padLeft(9)}'
      '${s.averageNodes.round().toString().padLeft(12)}${s.averageTimeMs.toStringAsFixed(1).padLeft(9)}'
      '${'${s.maxTimeMs}'.padLeft(9)}${'${s.overruns}'.padLeft(11)}${'${s.illegalMoves}'.padLeft(10)}'
      '${'${s.crashes}'.padLeft(10)}';
}
