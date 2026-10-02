import 'package:ace/chess_core/referee.dart';
import 'package:ace/match/opening_book_data.dart';

/// One opening line: UCI moves played from the standard start position.
class Opening {
  final int index; // 0-based position in the book
  final List<String> moves;

  const Opening(this.index, this.moves);
}

class OpeningBook {
  final List<Opening> openings;
  final List<String> warnings; // lines that were skipped, and why

  OpeningBook._(this.openings, this.warnings);

  /// The 500 lines in opening_book_data.dart.
  factory OpeningBook.standard() => OpeningBook.fromUciLines(openingBook);

  /// Each line is space-separated UCI moves from the standard start position.
  /// Every line is checked by the referee; illegal lines and lines that end the game are skipped.
  factory OpeningBook.fromUciLines(List<String> lines) {
    final openings = <Opening>[];
    final warnings = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final moves = lines[i].trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
      final referee = Referee(Referee.standardStartFen);
      String? problem;
      for (final move in moves) {
        problem = referee.tryPlayUci(move);
        if (problem != null) break;
      }
      problem ??= referee.checkGameEnd() == null ? null : 'the game is already over';

      if (problem != null) {
        warnings.add('Opening ${i + 1}: $problem (skipped)');
      } else {
        openings.add(Opening(i, List.unmodifiable(moves)));
      }
    }
    return OpeningBook._(List.unmodifiable(openings), List.unmodifiable(warnings));
  }
}
