import 'dart:math';

import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_stats.dart';

/// A move is flagged when the mover's own win chance (derived from its eval) falls by at least this many percentage
/// points by its next turn, meaning it missed something in the opponent's reply. 20 is Lichess's "mistake" level.
/// Using win chance rather than raw centipawns ignores swings that don't matter, like +17 falling to +8.
const int suspiciousWinDrop = 20;

/// A game counts as "lost from a winning position" if the loser once reported at least this much
const int winningCp = 300;

const int _scoreClamp = 2000; // Mate scores are clamped so one mate swing doesn't dwarf everything else

class SuspiciousMove {
  final int gameNumber;
  final int ply; // 0-based index into the game's moves
  final String label; // Engine that played it
  final String moveText; // e.g. "23... Nxe5"
  final String fenBefore;
  final int winDrop; // Percentage points
  final String explanation;

  SuspiciousMove({
    required this.gameNumber,
    required this.ply,
    required this.label,
    required this.moveText,
    required this.fenBefore,
    required this.winDrop,
    required this.explanation,
  });

  Map<String, dynamic> toJson() => {
        "game": gameNumber,
        "ply": ply,
        "engine": label,
        "move": moveText,
        "fen": fenBefore,
        "winDrop": winDrop,
        "explanation": explanation,
      };

  factory SuspiciousMove.fromJson(Map<String, dynamic> json) => SuspiciousMove(
        gameNumber: json["game"],
        ply: json["ply"],
        label: json["engine"],
        moveText: json["move"],
        fenBefore: json["fen"],
        winDrop: json["winDrop"],
        explanation: json["explanation"],
      );
}

/// Win chance (0-100) for a centipawn eval, using the same curve as Lichess
double winChance(int scoreCp) {
  int clamped = scoreCp.clamp(-_scoreClamp, _scoreClamp);
  return 50 + 50 * (2 / (1 + exp(-0.00368208 * clamped)) - 1);
}

/// e.g. "23. Nf3" or "23... Nf3" (games start from the standard position)
String moveText(GameRecord game, int ply) => "${ply ~/ 2 + 1}${ply.isEven ? "." : "..."} ${game.moves[ply].san}";

/// How much the mover's win chance fell from the move at [ply] to their next move, or null if it isn't a mistake
({int drop, String explanation})? _evalDrop(GameRecord game, int ply) {
  MoveRecord move = game.moves[ply];
  int? before = move.comparableScore;
  if (move.book || before == null) return null;

  String? explanation;
  double after;
  if (ply == game.moves.length - 2 && game.termination == Termination.checkmate) {
    // Mated straight after this move
    after = 0;
    explanation = "was mated by ${game.moves[ply + 1].san} straight after (eval was ${move.scoreText})";
  } else {
    if (ply + 2 >= game.moves.length) return null;
    MoveRecord next = game.moves[ply + 2];
    if (next.book || next.comparableScore == null) return null;
    after = winChance(next.comparableScore!);
    explanation = "eval fell from ${move.scoreText} to ${next.scoreText} "
        "(win chance ${winChance(before).round()}% -> ${after.round()}%) after the reply ${game.moves[ply + 1].san}";
  }

  int drop = (winChance(before) - after).round();
  if (drop < suspiciousWinDrop) return null;
  return (drop: drop, explanation: explanation);
}

/// Marks likely mistakes in [game] by setting [MoveRecord.suspicion]: moves after which the engine's own eval
/// dropped sharply by its next turn, meaning it missed the opponent's reply.
void flagSuspiciousMoves(GameRecord game) {
  for (int ply = 0; ply < game.moves.length; ply++) {
    game.moves[ply].suspicion = _evalDrop(game, ply)?.explanation;
  }
}

/// All flagged moves in a match, biggest win chance drop first
List<SuspiciousMove> suspiciousMoves(List<GameRecord> games) {
  List<SuspiciousMove> found = [];
  for (GameRecord game in games) {
    List<String>? fens;
    for (int ply = 0; ply < game.moves.length; ply++) {
      var drop = _evalDrop(game, ply);
      if (drop == null) continue;
      fens ??= game.positions();
      found.add(SuspiciousMove(
        gameNumber: game.gameNumber,
        ply: ply,
        label: game.moverAt(ply).label,
        moveText: moveText(game, ply),
        fenBefore: fens[ply],
        winDrop: drop.drop,
        explanation: drop.explanation,
      ));
    }
  }
  found.sort((a, b) => b.winDrop.compareTo(a.winDrop));
  return found;
}

/// Games the loser once thought it was clearly winning: (game number, loser, best eval it reported, ply)
List<({int gameNumber, String loser, String bestEval, int ply})> lostFromWinning(List<GameRecord> games) {
  var found = <({int gameNumber, String loser, String bestEval, int ply})>[];
  for (GameRecord game in games) {
    if (game.result == "1/2-1/2") continue;
    String loser = game.result == "1-0" ? game.black.label : game.white.label;
    int bestPly = -1;
    int best = -1 << 30;
    for (int ply = 0; ply < game.moves.length; ply++) {
      int? score = game.moves[ply].comparableScore;
      if (game.moverAt(ply).label == loser && score != null && score > best) {
        best = score;
        bestPly = ply;
      }
    }
    if (best >= winningCp) {
      found.add((gameNumber: game.gameNumber, loser: loser, bestEval: game.moves[bestPly].scoreText, ply: bestPly));
    }
  }
  return found;
}

/// Human readable match report
String buildReport({
  required MatchStats stats,
  required List<GameRecord> games,
  required MatchPlayer engine1,
  required MatchPlayer engine2,
  required bool complete,
  int maxSuspicious = 25,
}) {
  StringBuffer out = StringBuffer();
  String percent(double value) => "${(value * 100).toStringAsFixed(1)}%";
  String number(double? value, [int decimals = 1]) => value == null ? "-" : value.toStringAsFixed(decimals);

  out.writeln("ACE engine match: ${engine1.label} vs ${engine2.label}${complete ? "" : " (stopped early)"}");
  out.writeln("=" * 60);
  out.writeln("${engine1.label}: engine ${engine1.engineId}, ${engine1.moveTimeMs}ms per move");
  out.writeln("${engine2.label}: engine ${engine2.engineId}, ${engine2.moveTimeMs}ms per move");
  out.writeln();

  double? error = stats.eloError95;
  out.writeln("Games played: ${stats.games}");
  out.writeln("${engine1.label}: ${stats.wins} wins, ${stats.draws} draws, ${stats.losses} losses "
      "(score ${percent(stats.score)})");
  out.writeln("Elo difference: ${MatchStats.formatElo(stats.elo)}"
      "${error == null ? "" : " ± ${error.round()} (95% confidence)"}");
  out.writeln("Likelihood ${engine1.label} is stronger: ${percent(stats.los)}");
  if (error != null) {
    double lower = stats.elo - error;
    double upper = stats.elo + error;
    String verdict = lower > 0
        ? "${engine1.label} is stronger"
        : upper < 0
            ? "${engine2.label} is stronger"
            : "no significant difference yet (the interval includes 0; play more games to narrow it)";
    out.writeln("Verdict: $verdict");
  }
  out.writeln();

  out.writeln("How games ended:");
  for (Termination termination in Termination.values) {
    int count = stats.terminations[termination] ?? 0;
    if (count > 0) out.writeln("  ${termination.description.padRight(36)} $count");
  }
  out.writeln();

  out.writeln("Engine stats:        ${engine1.label.padRight(16)} ${engine2.label}");
  void row(String name, String a, String b) => out.writeln("  ${name.padRight(18)} ${a.padRight(16)} $b");
  row("average depth", number(stats.engine1.averageDepth), number(stats.engine2.averageDepth));
  row("average nodes", number(stats.engine1.averageNodes, 0), number(stats.engine2.averageNodes, 0));
  row("average time (ms)", number(stats.engine1.averageTimeMs, 0), number(stats.engine2.averageTimeMs, 0));
  row("max time (ms)", "${stats.engine1.maxTimeMs}", "${stats.engine2.maxTimeMs}");
  row("time overruns", "${stats.engine1.timeOverruns}", "${stats.engine2.timeOverruns}");
  row("illegal/no move", "${stats.engine1.infractionLosses}", "${stats.engine2.infractionLosses}");
  out.writeln();

  List<GameRecord> infractions = games
      .where((game) => const [Termination.illegalMove, Termination.noMove, Termination.engineError]
          .contains(game.termination))
      .toList();
  if (infractions.isNotEmpty) {
    out.writeln("Games lost by illegal move / no move / error:");
    for (GameRecord game in infractions) {
      out.writeln("  game ${game.gameNumber}: ${game.termination.description}: ${game.terminationDetail ?? ""}");
    }
    out.writeln();
  }

  var thrown = lostFromWinning(games);
  if (thrown.isNotEmpty) {
    out.writeln("Games lost after the loser reported >= +${(winningCp / 100).toStringAsFixed(2)}:");
    for (var game in thrown.take(maxSuspicious)) {
      out.writeln("  game ${game.gameNumber}: ${game.loser} was at ${game.bestEval} (ply ${game.ply + 1})");
    }
    if (thrown.length > maxSuspicious) out.writeln("  ... and ${thrown.length - maxSuspicious} more");
    out.writeln();
  }

  List<SuspiciousMove> suspicious = suspiciousMoves(games);
  out.writeln("Suspicious moves (the engine's own win chance fell >= $suspiciousWinDrop points by its next move): "
      "${suspicious.length}");
  for (SuspiciousMove move in suspicious.take(maxSuspicious)) {
    out.writeln("  game ${move.gameNumber}, ply ${move.ply + 1}, ${move.moveText} (${move.label}): ${move.explanation}");
    out.writeln("    FEN before: ${move.fenBefore}");
  }
  if (suspicious.length > maxSuspicious) {
    out.writeln("  ... and ${suspicious.length - maxSuspicious} more (all are marked with ? in games.pgn)");
  }
  out.writeln();
  out.writeln("Inspect a flagged move (shows the engine's top moves in the position before it):");
  out.writeln("  dart run bin/inspect.dart --engine ${engine1.engineId} --pgn <match folder>/games.pgn --game N --ply P");
  out.writeln("PGN comments read: eval (mover's view)/depth, time, nodes; pv = the line the engine expected.");

  return out.toString().replaceAll(RegExp(r"\n{3,}"), "\n\n");
}

/// Number of flagged moves, used for the live UI
int suspiciousCount(List<GameRecord> games) {
  return games.fold(0, (count, game) => count + game.moves.where((move) => move.suspicion != null).length);
}
