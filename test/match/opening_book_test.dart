import 'package:ace/match/opening_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpeningBook.fromUciLines', () {
    test('loads valid lines, keeping their original index and move list', () {
      final book = OpeningBook.fromUciLines(['e2e4 e7e5', 'd2d4 d7d5']);

      expect(book.warnings, isEmpty);
      expect(book.openings, hasLength(2));
      expect(book.openings[0].index, 0);
      expect(book.openings[0].moves, ['e2e4', 'e7e5']);
      expect(book.openings[1].index, 1);
      expect(book.openings[1].moves, ['d2d4', 'd7d5']);
    });

    test('skips a line with an illegal move and warns, without renumbering the rest', () {
      final book = OpeningBook.fromUciLines(['e2e4 e7e5', 'e2e5', 'd2d4 d7d5']);

      expect(book.openings, hasLength(2));
      expect(book.openings[0].index, 0);
      expect(book.openings[1].index, 2); // the broken line at index 1 is skipped entirely
      expect(book.warnings, hasLength(1));
      expect(book.warnings.single, contains('Opening 2'));
    });

    test('skips a line that already ends the game and warns', () {
      final book = OpeningBook.fromUciLines(['f2f3 e7e5 g2g4 d8h4']);

      expect(book.openings, isEmpty);
      expect(book.warnings, hasLength(1));
      expect(book.warnings.single, contains('already over'));
    });

    test('an empty list of lines produces an empty book with no warnings', () {
      final book = OpeningBook.fromUciLines([]);

      expect(book.openings, isEmpty);
      expect(book.warnings, isEmpty);
    });
  });

  group('OpeningBook.standard', () {
    test('loads the bundled 500-line opening book with no warnings', () {
      final book = OpeningBook.standard();

      expect(book.warnings, isEmpty);
      expect(book.openings, hasLength(500));
      for (final opening in book.openings) {
        expect(opening.moves, hasLength(16));
      }
    });
  });
}
