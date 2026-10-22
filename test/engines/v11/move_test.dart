import 'package:ace/engines/v11/core/board.dart';
import 'package:ace/engines/v11/core/move.dart';
import 'package:ace/engines/v11/core/move_generator.dart';
import 'package:ace/engines/v11/core/piece.dart';
import 'package:ace/engines/v11/core/zobrist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => Zobrist());

  group('encode round trip', () {
    test('every from/to/flag survives encode -> decode', () {
      int cases = 0;
      for (int from = 0; from < 64; from++) {
        for (int to = 0; to < 64; to++) {
          for (int flag = 0; flag < 8; flag++) {
            final m = Move.encode(from, to, flag);
            expect(m.from, from);
            expect(m.to, to);
            expect(m.flag, flag);
            cases++;
          }
        }
      }
      expect(cases, 32768);
    });

    test('flag defaults to 0', () {
      expect(Move.encode(1, 2).flag, 0);
    });
  });

  group('named constructor matches flags', () {
    void check(
      Move m, {
      required int flag,
      bool enPassant = false,
      bool castling = false,
      bool twoForward = false,
      int promotion = 0,
      int piece = Piece.none,
    }) {
      expect(m.flag, flag);
      expect(m.enPassantCapture, enPassant);
      expect(m.castling, castling);
      expect(m.pawnTwoForward, twoForward);
      expect(m.promotion, promotion);
      expect(m.isPromotion, promotion != 0);
      expect(m.promotingPiece(), piece);
      expect(m.from, 52);
      expect(m.to, 36);
    }

    test('normal', () {
      check(Move(startingSquare: 52, targetSquare: 36), flag: 0);
    });

    test('en passant', () {
      check(Move(startingSquare: 52, targetSquare: 36, enPassantCapture: true), flag: 1, enPassant: true);
    });

    test('castling', () {
      check(Move(startingSquare: 52, targetSquare: 36, castling: true), flag: 2, castling: true);
    });

    test('pawn two forward', () {
      check(Move(startingSquare: 52, targetSquare: 36, pawnTwoForward: true), flag: 3, twoForward: true);
    });

    test('promotions', () {
      const pieces = {1: Piece.queen, 2: Piece.knight, 3: Piece.rook, 4: Piece.bishop};
      pieces.forEach((promo, piece) {
        check(
          Move(startingSquare: 52, targetSquare: 36, promotion: promo),
          flag: promo + 3,
          promotion: promo,
          piece: piece,
        );
      });
    });
  });

  group('uci', () {
    test('quiet move', () {
      expect(Move(startingSquare: 52, targetSquare: 36).uci, 'e2e4');
    });

    test('promotions', () {
      // e7 = 12, e8 = 4
      const suffix = {1: 'q', 2: 'n', 3: 'r', 4: 'b'};
      suffix.forEach((promo, s) {
        expect(Move(startingSquare: 12, targetSquare: 4, promotion: promo).uci, 'e7e8$s');
      });
    });
  });

  group('no move', () {
    test('Move.invalid is zero and isNoMove', () {
      expect(Move.invalid.isNoMove, isTrue);
      expect(Move.invalid.value, 0);
    });

    test('no legal move from start position isNoMove', () {
      final moves = MoveGenerator().generateLegalMoves(Board());
      expect(moves, hasLength(20));
      expect(moves.any((m) => m.isNoMove), isFalse);
    });
  });

  group('equality', () {
    test('same fields are equal', () {
      final a = Move(startingSquare: 12, targetSquare: 4, promotion: 1);
      final b = Move(startingSquare: 12, targetSquare: 4, promotion: 1);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('different flag is not equal', () {
      final a = Move(startingSquare: 12, targetSquare: 4, promotion: 1);
      final b = Move(startingSquare: 12, targetSquare: 4, promotion: 2);
      expect(a == b, isFalse);
      expect(Move.encode(1, 2, 0) == Move.encode(1, 2, 3), isFalse);
    });
  });
}
