import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('start position', () {
    final fen = FenPosition.parse(FenPosition.startingPosition);
    expect(fen.position[0], Piece.black | Piece.rook); // a8
    expect(fen.position[60], Piece.white | Piece.king); // e1
    expect(fen.whiteToMove, isTrue);
    expect([fen.whiteCastleKingSide, fen.whiteCastleQueenSide, fen.blackCastleKingSide, fen.blackCastleQueenSide],
        everyElement(isTrue));
    expect(fen.enPassantSquare, -1);
    expect(fen.halfmoveClock, 0);
    expect(fen.fullmoveNumber, 1);
  });

  test('en passant square, no castling, clocks', () {
    final fen = FenPosition.parse('rnbqkbnr/pppp1ppp/8/8/4Pp2/8/PPPP2PP/RNBQKBNR b - e3 37 80');
    expect(fen.whiteToMove, isFalse);
    expect(fen.enPassantSquare, 44); // e3
    expect(fen.whiteCastleKingSide || fen.blackCastleQueenSide, isFalse);
    expect(fen.halfmoveClock, 37);
    expect(fen.fullmoveNumber, 80);
  });

  test('4-field FEN defaults the clocks', () {
    final fen = FenPosition.parse('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -');
    expect(fen.halfmoveClock, 0);
    expect(fen.fullmoveNumber, 1);
  });
}
