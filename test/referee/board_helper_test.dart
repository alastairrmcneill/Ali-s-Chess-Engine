import 'package:ace/referee/rules/board_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardHelper', () {
    test('squareName returns correct name for index 0', () {
      expect(BoardHelper.squareName(0), 'a8');
    });
    test('squareName returns correct name for index 63', () {
      expect(BoardHelper.squareName(63), 'h1');
    });

    test('squareIndex returns correct index for square a8', () {
      expect(BoardHelper.squareIndex('a8'), 0);
    });
    test('squareIndex returns correct index for square h1', () {
      expect(BoardHelper.squareIndex('h1'), 63);
    });
  });
}
