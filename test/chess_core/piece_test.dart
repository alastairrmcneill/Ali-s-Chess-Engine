import 'package:ace/chess_core/notation/piece.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Piece constants', () {
    test('has piece type constants', () {
      expect(Piece.none, 0);
      expect(Piece.king, 1);
      expect(Piece.pawn, 2);
      expect(Piece.knight, 3);
      expect(Piece.bishop, 4);
      expect(Piece.rook, 5);
      expect(Piece.queen, 6);
    });

    test('has color constants', () {
      expect(Piece.white, 0);
      expect(Piece.black, 8);
    });

    test('has combined piece-color constants', () {
      expect(Piece.whiteKing, 1);
      expect(Piece.whitePawn, 2);
      expect(Piece.whiteKnight, 3);
      expect(Piece.whiteBishop, 4);
      expect(Piece.whiteRook, 5);
      expect(Piece.whiteQueen, 6);
      expect(Piece.blackKing, 9);
      expect(Piece.blackPawn, 10);
      expect(Piece.blackKnight, 11);
      expect(Piece.blackBishop, 12);
      expect(Piece.blackRook, 13);
      expect(Piece.blackQueen, 14);
    });

    test('pieceList contains all pieces', () {
      expect(
        Piece.pieceList,
        [
          Piece.whiteKing,
          Piece.whitePawn,
          Piece.whiteKnight,
          Piece.whiteBishop,
          Piece.whiteRook,
          Piece.whiteQueen,
          Piece.blackKing,
          Piece.blackPawn,
          Piece.blackKnight,
          Piece.blackBishop,
          Piece.blackRook,
          Piece.blackQueen,
        ],
      );
    });
  });

  group('Piece.isColor', () {
    test('returns true for white pieces with white color', () {
      expect(Piece.isColor(Piece.whiteKing, Piece.white), true);
      expect(Piece.isColor(Piece.whitePawn, Piece.white), true);
      expect(Piece.isColor(Piece.whiteQueen, Piece.white), true);
    });

    test('returns true for black pieces with black color', () {
      expect(Piece.isColor(Piece.blackKing, Piece.black), true);
      expect(Piece.isColor(Piece.blackPawn, Piece.black), true);
      expect(Piece.isColor(Piece.blackQueen, Piece.black), true);
    });

    test('returns false for white pieces with black color', () {
      expect(Piece.isColor(Piece.whiteKing, Piece.black), false);
      expect(Piece.isColor(Piece.whitePawn, Piece.black), false);
    });

    test('returns false for black pieces with white color', () {
      expect(Piece.isColor(Piece.blackKing, Piece.white), false);
      expect(Piece.isColor(Piece.blackPawn, Piece.white), false);
    });

    test('returns false for empty square (0)', () {
      expect(Piece.isColor(Piece.none, Piece.white), false);
      expect(Piece.isColor(Piece.none, Piece.black), false);
    });
  });

  group('Piece.color', () {
    test('returns white for white pieces', () {
      expect(Piece.color(Piece.whiteKing), Piece.white);
      expect(Piece.color(Piece.whitePawn), Piece.white);
      expect(Piece.color(Piece.whiteRook), Piece.white);
    });

    test('returns black for black pieces', () {
      expect(Piece.color(Piece.blackKing), Piece.black);
      expect(Piece.color(Piece.blackPawn), Piece.black);
      expect(Piece.color(Piece.blackRook), Piece.black);
    });

    test('returns 0 for empty square', () {
      expect(Piece.color(Piece.none), 0);
    });
  });

  group('Piece.type', () {
    test('returns type for white pieces', () {
      expect(Piece.type(Piece.whiteKing), Piece.king);
      expect(Piece.type(Piece.whitePawn), Piece.pawn);
      expect(Piece.type(Piece.whiteKnight), Piece.knight);
      expect(Piece.type(Piece.whiteBishop), Piece.bishop);
      expect(Piece.type(Piece.whiteRook), Piece.rook);
      expect(Piece.type(Piece.whiteQueen), Piece.queen);
    });

    test('returns type for black pieces', () {
      expect(Piece.type(Piece.blackKing), Piece.king);
      expect(Piece.type(Piece.blackPawn), Piece.pawn);
      expect(Piece.type(Piece.blackKnight), Piece.knight);
      expect(Piece.type(Piece.blackBishop), Piece.bishop);
      expect(Piece.type(Piece.blackRook), Piece.rook);
      expect(Piece.type(Piece.blackQueen), Piece.queen);
    });

    test('returns 0 for empty square', () {
      expect(Piece.type(Piece.none), 0);
    });
  });

  group('Piece.isQueenOrBishop', () {
    test('returns true for white queen and bishop', () {
      expect(Piece.isQueenOrBishop(Piece.whiteQueen), true);
      expect(Piece.isQueenOrBishop(Piece.whiteBishop), true);
    });

    test('returns true for black queen and bishop', () {
      expect(Piece.isQueenOrBishop(Piece.blackQueen), true);
      expect(Piece.isQueenOrBishop(Piece.blackBishop), true);
    });

    test('returns false for other pieces', () {
      expect(Piece.isQueenOrBishop(Piece.whiteKing), false);
      expect(Piece.isQueenOrBishop(Piece.whitePawn), false);
      expect(Piece.isQueenOrBishop(Piece.whiteKnight), false);
      expect(Piece.isQueenOrBishop(Piece.whiteRook), false);
      expect(Piece.isQueenOrBishop(Piece.blackKing), false);
      expect(Piece.isQueenOrBishop(Piece.none), false);
    });
  });

  group('Piece.isQueenOrRook', () {
    test('returns true for white queen and rook', () {
      expect(Piece.isQueenOrRook(Piece.whiteQueen), true);
      expect(Piece.isQueenOrRook(Piece.whiteRook), true);
    });

    test('returns true for black queen and rook', () {
      expect(Piece.isQueenOrRook(Piece.blackQueen), true);
      expect(Piece.isQueenOrRook(Piece.blackRook), true);
    });

    test('returns false for other pieces', () {
      expect(Piece.isQueenOrRook(Piece.whiteKing), false);
      expect(Piece.isQueenOrRook(Piece.whitePawn), false);
      expect(Piece.isQueenOrRook(Piece.whiteKnight), false);
      expect(Piece.isQueenOrRook(Piece.whiteBishop), false);
      expect(Piece.isQueenOrRook(Piece.blackKing), false);
      expect(Piece.isQueenOrRook(Piece.none), false);
    });
  });

  group('Piece.toFenChar', () {
    test('converts white pieces to uppercase', () {
      expect(Piece.toFenChar(Piece.whiteKing), 'K');
      expect(Piece.toFenChar(Piece.whitePawn), 'P');
      expect(Piece.toFenChar(Piece.whiteKnight), 'N');
      expect(Piece.toFenChar(Piece.whiteBishop), 'B');
      expect(Piece.toFenChar(Piece.whiteRook), 'R');
      expect(Piece.toFenChar(Piece.whiteQueen), 'Q');
    });

    test('converts black pieces to lowercase', () {
      expect(Piece.toFenChar(Piece.blackKing), 'k');
      expect(Piece.toFenChar(Piece.blackPawn), 'p');
      expect(Piece.toFenChar(Piece.blackKnight), 'n');
      expect(Piece.toFenChar(Piece.blackBishop), 'b');
      expect(Piece.toFenChar(Piece.blackRook), 'r');
      expect(Piece.toFenChar(Piece.blackQueen), 'q');
    });

    test('converts empty square to space', () {
      expect(Piece.toFenChar(Piece.none), ' ');
    });
  });

  group('Piece.print', () {
    test('prints king as k', () {
      expect(Piece.print(Piece.whiteKing), 'k');
      expect(Piece.print(Piece.blackKing), 'k');
    });

    test('prints pawn as p', () {
      expect(Piece.print(Piece.whitePawn), 'p');
      expect(Piece.print(Piece.blackPawn), 'p');
    });

    test('prints knight as n', () {
      expect(Piece.print(Piece.whiteKnight), 'n');
      expect(Piece.print(Piece.blackKnight), 'n');
    });

    test('prints bishop as b', () {
      expect(Piece.print(Piece.whiteBishop), 'b');
      expect(Piece.print(Piece.blackBishop), 'b');
    });

    test('prints rook as r', () {
      expect(Piece.print(Piece.whiteRook), 'r');
      expect(Piece.print(Piece.blackRook), 'r');
    });

    test('prints queen as q', () {
      expect(Piece.print(Piece.whiteQueen), 'q');
      expect(Piece.print(Piece.blackQueen), 'q');
    });

    test('prints empty square as 0', () {
      expect(Piece.print(Piece.none), '0');
    });
  });

  group('Piece masks', () {
    test('typeMask extracts piece type', () {
      expect(Piece.whiteKing & Piece.typeMask, Piece.king);
      expect(Piece.blackQueen & Piece.typeMask, Piece.queen);
    });

    test('colorMask extracts color', () {
      expect(Piece.whiteKing & Piece.colorMask, Piece.white);
      expect(Piece.blackKing & Piece.colorMask, Piece.black);
    });
  });
}
