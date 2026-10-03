import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/engines/v1/core/piece.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Move creation', () {
    test('creates a basic move with start and target squares', () {
      final move = Move(startingSquare: 12, targetSquare: 28);
      expect(move.startingSquare, 12);
      expect(move.targetSquare, 28);
      expect(move.enPassantCapture, false);
      expect(move.pawnTwoForward, false);
      expect(move.promotion, 0);
      expect(move.castling, false);
    });

    test('creates an en passant capture move', () {
      final move = Move(
        startingSquare: 32,
        targetSquare: 40,
        enPassantCapture: true,
      );
      expect(move.enPassantCapture, true);
    });

    test('creates a pawn two forward move', () {
      final move = Move(
        startingSquare: 48,
        targetSquare: 32,
        pawnTwoForward: true,
      );
      expect(move.pawnTwoForward, true);
    });

    test('creates a promotion move', () {
      final move = Move(
        startingSquare: 8,
        targetSquare: 0,
        promotion: 1, // queen
      );
      expect(move.promotion, 1);
    });

    test('creates a castling move', () {
      final move = Move(
        startingSquare: 60,
        targetSquare: 62,
        castling: true,
      );
      expect(move.castling, true);
    });

    test('invalid move has -1 squares', () {
      final move = Move.invalid;
      expect(move.startingSquare, -1);
      expect(move.targetSquare, -1);
    });
  });

  group('promotingPiece', () {
    test('returns queen for promotion code 1', () {
      final move = Move(startingSquare: 8, targetSquare: 0, promotion: 1);
      expect(move.promotingPiece(), Piece.queen);
    });

    test('returns knight for promotion code 2', () {
      final move = Move(startingSquare: 8, targetSquare: 0, promotion: 2);
      expect(move.promotingPiece(), Piece.knight);
    });

    test('returns rook for promotion code 3', () {
      final move = Move(startingSquare: 8, targetSquare: 0, promotion: 3);
      expect(move.promotingPiece(), Piece.rook);
    });

    test('returns bishop for promotion code 4', () {
      final move = Move(startingSquare: 8, targetSquare: 0, promotion: 4);
      expect(move.promotingPiece(), Piece.bishop);
    });

    test('returns none for unknown promotion code', () {
      final move = Move(startingSquare: 8, targetSquare: 0, promotion: 99);
      expect(move.promotingPiece(), Piece.none);
    });

    test('returns none for no promotion (0)', () {
      final move = Move(startingSquare: 12, targetSquare: 28);
      expect(move.promotingPiece(), Piece.none);
    });
  });

  group('toChessNotation', () {
    test('converts e2 to e4 correctly', () {
      final move = Move(
        startingSquare: BoardHelper.squareIndex('e2'),
        targetSquare: BoardHelper.squareIndex('e4'),
      );
      expect(move.toChessNotation(), 'e2e4');
    });

    test('converts a1 to a2 correctly', () {
      final move = Move(
        startingSquare: BoardHelper.squareIndex('a1'),
        targetSquare: BoardHelper.squareIndex('a2'),
      );
      expect(move.toChessNotation(), 'a1a2');
    });

    test('converts h7 to h8 correctly', () {
      final move = Move(
        startingSquare: BoardHelper.squareIndex('h7'),
        targetSquare: BoardHelper.squareIndex('h8'),
      );
      expect(move.toChessNotation(), 'h7h8');
    });

    test('handles castling kingside', () {
      final move = Move(
        startingSquare: BoardHelper.squareIndex('e1'),
        targetSquare: BoardHelper.squareIndex('g1'),
        castling: true,
      );
      expect(move.toChessNotation(), 'e1g1');
    });

    test('handles castling queenside', () {
      final move = Move(
        startingSquare: BoardHelper.squareIndex('e8'),
        targetSquare: BoardHelper.squareIndex('c8'),
        castling: true,
      );
      expect(move.toChessNotation(), 'e8c8');
    });

    test('all board squares round-trip correctly', () {
      final files = 'abcdefgh';
      final ranks = '12345678';
      for (int i = 0; i < files.length; i++) {
        for (int j = 0; j < ranks.length; j++) {
          final square = '${files[i]}${ranks[j]}';
          final index = BoardHelper.squareIndex(square);
          final move = Move(startingSquare: index, targetSquare: index);
          expect(move.toChessNotation().substring(0, 2), square);
        }
      }
    });
  });

  group('isSameAs', () {
    test('returns true for identical moves', () {
      final move1 = Move(startingSquare: 12, targetSquare: 28);
      final move2 = Move(startingSquare: 12, targetSquare: 28);
      expect(move1.isSameAs(move2), true);
    });

    test('returns false for different starting squares', () {
      final move1 = Move(startingSquare: 12, targetSquare: 28);
      final move2 = Move(startingSquare: 13, targetSquare: 28);
      expect(move1.isSameAs(move2), false);
    });

    test('returns false for different target squares', () {
      final move1 = Move(startingSquare: 12, targetSquare: 28);
      final move2 = Move(startingSquare: 12, targetSquare: 29);
      expect(move1.isSameAs(move2), false);
    });

    test('returns false if one is en passant and other is not', () {
      final move1 = Move(startingSquare: 32, targetSquare: 40);
      final move2 = Move(
        startingSquare: 32,
        targetSquare: 40,
        enPassantCapture: true,
      );
      expect(move1.isSameAs(move2), false);
    });

    test('returns false if promotions differ', () {
      final move1 = Move(startingSquare: 8, targetSquare: 0, promotion: 1);
      final move2 = Move(startingSquare: 8, targetSquare: 0, promotion: 2);
      expect(move1.isSameAs(move2), false);
    });

    test('returns false if castling status differs', () {
      final move1 = Move(startingSquare: 60, targetSquare: 62);
      final move2 = Move(startingSquare: 60, targetSquare: 62, castling: true);
      expect(move1.isSameAs(move2), false);
    });

    test('two identical complex moves are the same', () {
      final move1 = Move(
        startingSquare: 8,
        targetSquare: 0,
        promotion: 1,
        pawnTwoForward: false,
        enPassantCapture: false,
        castling: false,
      );
      final move2 = Move(
        startingSquare: 8,
        targetSquare: 0,
        promotion: 1,
        pawnTwoForward: false,
        enPassantCapture: false,
        castling: false,
      );
      expect(move1.isSameAs(move2), true);
    });
  });

  group('toString', () {
    test('displays from and to squares', () {
      final move = Move(startingSquare: 12, targetSquare: 28);
      final str = move.toString();
      expect(str, contains('From: 12'));
      expect(str, contains('To: 28'));
    });

    test('handles invalid moves', () {
      final move = Move.invalid;
      final str = move.toString();
      expect(str, contains('From: -1'));
      expect(str, contains('To: -1'));
    });
  });

  group('edge cases', () {
    test('move between same square is valid', () {
      final move = Move(startingSquare: 32, targetSquare: 32);
      expect(move.startingSquare, 32);
      expect(move.targetSquare, 32);
    });

    test('combining multiple flags', () {
      final move = Move(
        startingSquare: 8,
        targetSquare: 0,
        enPassantCapture: true,
        pawnTwoForward: true,
        promotion: 1,
        castling: true,
      );
      expect(move.enPassantCapture, true);
      expect(move.pawnTwoForward, true);
      expect(move.promotion, 1);
      expect(move.castling, true);
    });

    test('all board squares as move targets', () {
      for (int i = 0; i < 64; i++) {
        for (int j = 0; j < 64; j++) {
          final move = Move(startingSquare: i, targetSquare: j);
          expect(move.startingSquare, i);
          expect(move.targetSquare, j);
        }
      }
    });
  });
}
