import 'package:ace/chess_core/rules/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameState', () {
    test('creates with default values', () {
      final state = GameState();
      expect(state.capturedPiece, 0);
      expect(state.enPassantSquare, -1);
      expect(state.whiteCastleKingSide, false);
      expect(state.whiteCastleQueenSide, false);
      expect(state.blackCastleKingSide, false);
      expect(state.blackCastleQueenSide, false);
      expect(state.fiftyMoveRule, 0);
      expect(state.zobristKey, -1);
    });

    test('creates with custom values', () {
      final state = GameState(
        capturedPiece: 6,
        enPassantSquare: 20,
        whiteCastleKingSide: true,
        whiteCastleQueenSide: false,
        blackCastleKingSide: true,
        blackCastleQueenSide: true,
        fiftyMoveRule: 5,
        zobristKey: 12345,
      );
      expect(state.capturedPiece, 6);
      expect(state.enPassantSquare, 20);
      expect(state.whiteCastleKingSide, true);
      expect(state.whiteCastleQueenSide, false);
      expect(state.blackCastleKingSide, true);
      expect(state.blackCastleQueenSide, true);
      expect(state.fiftyMoveRule, 5);
      expect(state.zobristKey, 12345);
    });

    group('castling rights', () {
      test('can enable white kingside castling', () {
        final state = GameState(whiteCastleKingSide: true);
        expect(state.whiteCastleKingSide, true);
      });

      test('can enable white queenside castling', () {
        final state = GameState(whiteCastleQueenSide: true);
        expect(state.whiteCastleQueenSide, true);
      });

      test('can enable black kingside castling', () {
        final state = GameState(blackCastleKingSide: true);
        expect(state.blackCastleKingSide, true);
      });

      test('can enable black queenside castling', () {
        final state = GameState(blackCastleQueenSide: true);
        expect(state.blackCastleQueenSide, true);
      });

      test('can combine multiple castling rights', () {
        final state = GameState(
          whiteCastleKingSide: true,
          whiteCastleQueenSide: true,
          blackCastleKingSide: true,
          blackCastleQueenSide: true,
        );
        expect(state.whiteCastleKingSide, true);
        expect(state.whiteCastleQueenSide, true);
        expect(state.blackCastleKingSide, true);
        expect(state.blackCastleQueenSide, true);
      });
    });

    group('toString', () {
      test('includes captured piece, en passant, and fifty move rule', () {
        final state = GameState(
          capturedPiece: 6,
          enPassantSquare: 20,
          fiftyMoveRule: 5,
        );
        final str = state.toString();
        expect(str, contains('CapturedPieceType: 6'));
        expect(str, contains('En Passant Square: 20'));
        expect(str, contains('50 Move Rule: 5'));
      });

      test('handles default values in toString', () {
        final state = GameState();
        final str = state.toString();
        expect(str, contains('CapturedPieceType: 0'));
        expect(str, contains('En Passant Square: -1'));
        expect(str, contains('50 Move Rule: 0'));
      });
    });

    group('en passant square', () {
      test('can set en passant square to -1 (no en passant)', () {
        final state = GameState(enPassantSquare: -1);
        expect(state.enPassantSquare, -1);
      });

      test('can set en passant square to valid board index', () {
        for (int i = 0; i < 64; i++) {
          final state = GameState(enPassantSquare: i);
          expect(state.enPassantSquare, i);
        }
      });
    });

    group('fifty move rule counter', () {
      test('tracks fifty move rule from 0 to 50', () {
        for (int i = 0; i <= 50; i++) {
          final state = GameState(fiftyMoveRule: i);
          expect(state.fiftyMoveRule, i);
        }
      });

      test('can exceed 50 moves', () {
        final state = GameState(fiftyMoveRule: 100);
        expect(state.fiftyMoveRule, 100);
      });
    });

    group('zobrist key', () {
      test('stores zobrist key', () {
        final state = GameState(zobristKey: 999999);
        expect(state.zobristKey, 999999);
      });

      test('handles negative zobrist key (-1 default)', () {
        final state = GameState(zobristKey: -1);
        expect(state.zobristKey, -1);
      });
    });

    group('captured piece', () {
      test('tracks captured piece type', () {
        for (int piece = 0; piece <= 14; piece++) {
          final state = GameState(capturedPiece: piece);
          expect(state.capturedPiece, piece);
        }
      });

      test('0 means no piece captured', () {
        final state = GameState(capturedPiece: 0);
        expect(state.capturedPiece, 0);
      });
    });
  });
}
