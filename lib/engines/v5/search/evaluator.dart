import 'package:ace/engines/v5/core/board.dart';
import 'package:ace/engines/v5/core/piece.dart';

class Evaluator {
  final pieceValues = {
    Piece.pawn: 100,
    Piece.rook: 500,
    Piece.knight: 300,
    Piece.bishop: 300,
    Piece.queen: 900,
    Piece.king: 10000,
  };

  int evaluate(Board board) {
    int whiteScore = 0;
    int blackScore = 0;
    board.position.forEach((piece) {
      if (piece != Piece.none) {
        if (Piece.isColor(piece, Piece.white)) {
          whiteScore += pieceValues[Piece.type(piece)]!;
        } else {
          blackScore += pieceValues[Piece.type(piece)]!;
        }
      }
    });

    int evaluation = whiteScore - blackScore;

    return board.whiteToPlay ? evaluation : -evaluation;
  }
}
