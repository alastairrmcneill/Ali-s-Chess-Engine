import 'package:ace/engines/v10/search/opening_book_data.dart';

class OpeningBook {
  String? pickMove(List<String> currentMoves) {
    final key = currentMoves.join(' ');

    final openings = openingBook.where((opening) => opening.startsWith(key)).toList();

    if (openings.isEmpty) {
      return null;
    }

    final nextMoves = openings.map((opening) => opening.split(' ')[currentMoves.length]).toList();

    nextMoves.shuffle();
    return nextMoves.first;
  }
}
