import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UciMove.parse - basic moves', () {
    test('parses a simple quiet move', () {
      final move = UciMove.parse('e2e4');
      expect(move.from, BoardHelper.squareIndex('e2'));
      expect(move.to, BoardHelper.squareIndex('e4'));
      expect(move.promotion, isNull);
    });

    test('parses the a1 corner square correctly', () {
      final move = UciMove.parse('a1a2');
      expect(move.from, 56);
      expect(move.to, 48);
    });

    test('parses the h8 corner square correctly', () {
      final move = UciMove.parse('h7h8');
      expect(move.from, BoardHelper.squareIndex('h7'));
      expect(move.to, 7);
    });
  });

  group('UciMove.parse - promotions', () {
    for (final piece in ['q', 'r', 'b', 'n']) {
      test('parses promotion to $piece', () {
        final move = UciMove.parse('e7e8$piece');
        expect(move.from, BoardHelper.squareIndex('e7'));
        expect(move.to, BoardHelper.squareIndex('e8'));
        expect(move.promotion, piece);
      });
    }

    test('lowercases an uppercase promotion letter', () {
      final move = UciMove.parse('e7e8Q');
      expect(move.promotion, 'q');
    });

    test('throws on an invalid promotion piece', () {
      expect(() => UciMove.parse('e7e8k'), throwsFormatException);
    });
  });

  group('UciMove.parse - invalid input', () {
    test('throws when the string is too short', () {
      expect(() => UciMove.parse('e2e'), throwsFormatException);
    });

    test('throws when the string is too long', () {
      expect(() => UciMove.parse('e2e4qq'), throwsFormatException);
    });

    test('throws on an empty string', () {
      expect(() => UciMove.parse(''), throwsFormatException);
    });

    test('throws on squares off the board', () {
      expect(() => UciMove.parse('e9e4'), throwsFormatException);
      expect(() => UciMove.parse('i2i4'), throwsFormatException);
    });
  });

  group('UciMove.toString', () {
    test('round-trips a quiet move', () {
      expect(UciMove.parse('e2e4').toString(), 'e2e4');
    });

    test('round-trips a promotion move', () {
      expect(UciMove.parse('e7e8q').toString(), 'e7e8q');
    });

    test('omits promotion when there is none', () {
      final move = UciMove(from: BoardHelper.squareIndex('g1'), to: BoardHelper.squareIndex('f3'));
      expect(move.toString(), 'g1f3');
    });
  });
}
