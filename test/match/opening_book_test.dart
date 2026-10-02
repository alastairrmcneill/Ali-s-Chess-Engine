import 'package:ace/match/opening_book.dart';
import 'package:ace/match/opening_book_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every line in opening_book_data.dart is legal and playable', () {
    final book = OpeningBook.standard();
    expect(book.warnings, isEmpty);
    expect(book.openings, hasLength(openingBook.length));
    expect(book.openings.first.moves, hasLength(16));
  });

  test('bad lines are skipped with a warning', () {
    final book = OpeningBook.fromUciLines(['e2e4 e7e5', 'e2e4 e2e4', 'f2f3 e7e5 g2g4 d8h4']);
    expect(book.openings.map((o) => o.index), [0]);
    expect(book.warnings, hasLength(2));
    expect(book.warnings[0], contains('Opening 2'));
    expect(book.warnings[1], contains('already over'));
  });
}
