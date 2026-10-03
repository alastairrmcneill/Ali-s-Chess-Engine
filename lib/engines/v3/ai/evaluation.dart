import 'package:ace/engines/v3/core/board.dart';
import 'package:ace/engines/v3/core/piece.dart';

/// Material only. No piece-square tables, no game phase.
class Evaluation {
  static const int pawnValue = 100;
  static const int knightValue = 300;
  static const int bishopValue = 300;
  static const int rookValue = 500;
  static const int queenValue = 900;

  static int _value(int type) {
    switch (type) {
      case Piece.pawn:
        return pawnValue;
      case Piece.knight:
        return knightValue;
      case Piece.bishop:
        return bishopValue;
      case Piece.rook:
        return rookValue;
      case Piece.queen:
        return queenValue;
      default:
        return 0;
    }
  }

  /// Centipawns from the point of view of the side to move.
  int evaluate(Board board) {
    int white = 0;
    int black = 0;
    for (final piece in board.position) {
      if (piece == Piece.none) continue;
      final value = _value(Piece.type(piece));
      if (Piece.isColor(piece, Piece.white)) {
        white += value;
      } else {
        black += value;
      }
    }
    final eval = white - black;
    return board.whiteToPlay ? eval : -eval;
  }
}
