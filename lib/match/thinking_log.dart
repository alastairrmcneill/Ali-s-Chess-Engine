import 'dart:convert';

import 'package:ace/match/game_record.dart';

/// One JSON object per engine move: the move it played, the line it expected, how deep it searched and how many
/// nodes it visited. Used for both match games and games played in the app, so a finished game can be reviewed
/// move by move.
class ThinkingLog {
  /// A single JSON line (no trailing newline).
  static String line({
    required int game,
    required int ply, // 1-based ply in the whole game, book moves included
    required bool white,
    required String move,
    required MoveStat stat,
  }) {
    return jsonEncode({
      'game': game,
      'ply': ply,
      'side': white ? 'white' : 'black',
      'move': move,
      'pv': stat.pv,
      'depth': stat.depth,
      'nodes': stat.nodes,
    });
  }

  /// One line per engine move of [record] whose engine reported a principal variation; empty otherwise.
  static List<String> linesForGame(GameRecord record) {
    final lines = <String>[];
    for (var i = 0; i < record.moveStats.length; i++) {
      final stat = record.moveStats[i];
      if (stat.pv == null) continue;
      final ply = record.bookPlies + i;
      lines.add(line(
        game: record.gameNumber,
        ply: ply + 1,
        white: record.engineMoveIsWhite(i),
        move: record.uciMoves[ply],
        stat: stat,
      ));
    }
    return lines;
  }
}
