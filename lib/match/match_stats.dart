import 'dart:math';

import 'package:ace/match/game_record.dart';

/// Per engine search statistics across a match
class PlayerStats {
  final String label;
  int engineMoves = 0;
  int totalDepth = 0;
  int depthCount = 0;
  int totalNodes = 0;
  int nodeCount = 0;
  int totalTimeMs = 0;
  int maxTimeMs = 0;
  int timeOverruns = 0; // Moves that took more than 1.5x the allowed time + 50ms
  int infractionLosses = 0; // Illegal move, no move or engine error

  PlayerStats(this.label);

  double? get averageDepth => depthCount == 0 ? null : totalDepth / depthCount;
  double? get averageNodes => nodeCount == 0 ? null : totalNodes / nodeCount;
  double? get averageTimeMs => engineMoves == 0 ? null : totalTimeMs / engineMoves;

  Map<String, dynamic> toJson() => {
        "label": label,
        "engineMoves": engineMoves,
        "averageDepth": averageDepth,
        "averageNodes": averageNodes,
        "averageTimeMs": averageTimeMs,
        "maxTimeMs": maxTimeMs,
        "timeOverruns": timeOverruns,
        "infractionLosses": infractionLosses,
      };
}

/// Results of a match from engine 1's point of view
class MatchStats {
  final String engine1Label;
  final String engine2Label;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  final Map<Termination, int> terminations = {};
  final PlayerStats engine1;
  final PlayerStats engine2;
  final List<double> _pairScores = []; // Average score of engine 1 per opening (both colours)

  MatchStats._(this.engine1Label, this.engine2Label)
      : engine1 = PlayerStats(engine1Label),
        engine2 = PlayerStats(engine2Label);

  factory MatchStats.fromGames(List<GameRecord> games, String engine1Label, String engine2Label) {
    MatchStats stats = MatchStats._(engine1Label, engine2Label);
    Map<int, List<double>> scoresByOpening = {};

    for (GameRecord game in games) {
      double score = game.scoreFor(engine1Label);
      if (score == 1) {
        stats.wins++;
      } else if (score == 0) {
        stats.losses++;
      } else {
        stats.draws++;
      }
      stats.terminations.update(game.termination, (count) => count + 1, ifAbsent: () => 1);
      scoresByOpening.putIfAbsent(game.openingIndex, () => []).add(score);

      // Engine search stats
      for (int ply = 0; ply < game.moves.length; ply++) {
        MoveRecord move = game.moves[ply];
        if (move.book) continue;
        MatchPlayer mover = game.moverAt(ply);
        PlayerStats player = mover.label == engine1Label ? stats.engine1 : stats.engine2;
        player.engineMoves++;
        if (move.depth != null) {
          player.totalDepth += move.depth!;
          player.depthCount++;
        }
        if (move.nodes != null) {
          player.totalNodes += move.nodes!;
          player.nodeCount++;
        }
        int time = move.timeMs ?? 0;
        player.totalTimeMs += time;
        player.maxTimeMs = max(player.maxTimeMs, time);
        if (time > mover.moveTimeMs * 1.5 + 50) player.timeOverruns++;
      }

      if (const [Termination.illegalMove, Termination.noMove, Termination.engineError].contains(game.termination)) {
        String loser = game.result == "1-0" ? game.black.label : game.white.label;
        (loser == engine1Label ? stats.engine1 : stats.engine2).infractionLosses++;
      }
    }

    for (List<double> scores in scoresByOpening.values) {
      stats._pairScores.add(scores.reduce((a, b) => a + b) / scores.length);
    }
    return stats;
  }

  int get games => wins + draws + losses;

  /// Engine 1's score as a fraction (0.5 = even)
  double get score => games == 0 ? 0.5 : (wins + draws / 2) / games;

  /// Elo difference of engine 1 over engine 2 implied by the score
  double get elo => eloFromScore(score);

  /// Half width of the 95% confidence interval for [elo], or null when there isn't enough data.
  /// Uses the spread of the per-opening pair scores, which accounts for colour-swapped games being correlated.
  double? get eloError95 {
    int n = _pairScores.length;
    if (n < 2) return null;
    double mean = _pairScores.reduce((a, b) => a + b) / n;
    double variance = _pairScores.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) / (n - 1);
    double standardError = sqrt(variance / n);
    if (standardError == 0) return null;
    // Early in a match the interval can run past 0% or 100%, so clamp it to keep the Elo finite
    double upper = eloFromScore(min(mean + 1.96 * standardError, 0.999));
    double lower = eloFromScore(max(mean - 1.96 * standardError, 0.001));
    return (upper - lower) / 2;
  }

  /// Likelihood of superiority: the probability engine 1 is genuinely stronger, given wins and losses
  double get los {
    if (wins + losses == 0) return 0.5;
    return 0.5 * (1 + erf((wins - losses) / sqrt(2.0 * (wins + losses))));
  }

  /// e.g. "ACE v2 +118 =150 -44 | +82 ± 30 Elo"
  String get summaryLine {
    double? error = eloError95;
    String eloText = "${formatElo(elo)}${error == null ? "" : " ± ${error.round()}"} Elo";
    return "$engine1Label +$wins =$draws -$losses | $eloText";
  }

  static String formatElo(double elo) {
    if (elo.isInfinite) return elo > 0 ? "+inf" : "-inf";
    return "${elo >= 0 ? "+" : ""}${elo.round()}";
  }

  static double eloFromScore(double score) {
    if (score <= 0) return double.negativeInfinity;
    if (score >= 1) return double.infinity;
    return -400 * log(1 / score - 1) / ln10;
  }

  /// Error function (Abramowitz and Stegun 7.1.26, accurate to about 1e-7)
  static double erf(double x) {
    double sign = x < 0 ? -1 : 1;
    x = x.abs();
    double t = 1 / (1 + 0.3275911 * x);
    double y = 1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) *
            t *
            exp(-x * x);
    return sign * y;
  }

  Map<String, dynamic> toJson() => {
        "engine1": engine1Label,
        "engine2": engine2Label,
        "games": games,
        "wins": wins,
        "draws": draws,
        "losses": losses,
        "score": score,
        "elo": elo.isFinite ? elo : null,
        "eloError95": eloError95,
        "los": los,
        "terminations": {for (MapEntry<Termination, int> entry in terminations.entries) entry.key.name: entry.value},
        "engine1Stats": engine1.toJson(),
        "engine2Stats": engine2.toJson(),
      };
}
