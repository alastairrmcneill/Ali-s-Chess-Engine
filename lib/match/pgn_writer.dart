import 'package:ace/chess_core/game_end.dart';
import 'package:ace/match/game_record.dart';

class PgnWriter {
  /// Evals at least this big are treated as "mate found" (v1's checkmate score is about ±1e9).
  static const int mateThreshold = 900000000;

  static String gameToPgn(GameRecord record, {required String event, required Duration moveTime, DateTime? date}) {
    final d = date ?? DateTime.now();
    final dateString = '${d.year}.${_two(d.month)}.${_two(d.day)}';
    final headers = {
      'Event': event,
      'Site': 'ACE match manager',
      'Date': dateString,
      'Round': '${record.gameNumber}',
      'White': record.whiteName,
      'Black': record.blackName,
      'Result': record.end.pgnResult,
      'Termination': record.end.termination.name,
      'PlyCount': '${record.sanMoves.length}',
      'TimeControl': 'movetime=${moveTime.inMilliseconds}ms',
      'Opening': 'book #${record.openingIndex + 1}',
    };

    final tokens = <String>[];
    for (int ply = 0; ply < record.sanMoves.length; ply++) {
      if (ply.isEven) tokens.add('${ply ~/ 2 + 1}.');
      tokens.add(record.sanMoves[ply]);
      if (ply == record.bookPlies - 1) tokens.add('{book}');
      final engineIndex = ply - record.bookPlies;
      if (engineIndex >= 0 && engineIndex < record.moveStats.length) {
        final comment = _comment(record.moveStats[engineIndex]);
        if (comment.isNotEmpty) tokens.add('{$comment}');
      }
    }
    if (record.end.termination == GameTermination.illegalMove || record.end.termination == GameTermination.engineError) {
      tokens.add('{forfeit: ${_escape(record.end.detail ?? record.end.termination.name)}}');
    }
    tokens.add(record.end.pgnResult);

    final buffer = StringBuffer();
    headers.forEach((key, value) => buffer.writeln('[$key "${_escapeHeader(value)}"]'));
    buffer.writeln();
    buffer.writeln(_wrap(tokens, 80));
    return buffer.toString();
  }

  /// e.g. "+0.31/7 98ms": eval in pawns from White's point of view, depth, time.
  static String _comment(MoveStat stat) {
    final parts = <String>[];
    var evalAndDepth = '';
    if (stat.evaluation != null) evalAndDepth = formatEval(stat.evaluation!);
    if (stat.depth != null) evalAndDepth += '/${stat.depth}';
    if (evalAndDepth.isNotEmpty) parts.add(evalAndDepth);
    parts.add('${stat.timeMs}ms');
    return parts.join(' ');
  }

  static String formatEval(int eval) {
    if (eval.abs() >= mateThreshold) return eval > 0 ? '+M' : '-M';
    final pawns = eval / 100;
    return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(2)}';
  }

  static String _wrap(List<String> tokens, int width) {
    final lines = <String>[];
    var line = '';
    for (final token in tokens) {
      if (line.isNotEmpty && line.length + 1 + token.length > width) {
        lines.add(line);
        line = token;
      } else {
        line = line.isEmpty ? token : '$line $token';
      }
    }
    if (line.isNotEmpty) lines.add(line);
    return lines.join('\n');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _escape(String s) => s.replaceAll('}', ')').replaceAll('{', '(');
  static String _escapeHeader(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
