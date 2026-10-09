import 'package:ace/engines/v6/core/board.dart';
import 'package:ace/engines/v6/core/move.dart';
import 'package:ace/engines/v6/core/piece.dart';

class MoveOrdering {
  final Map<int, int> pieceValues = {
    Piece.none: 1, // En passant doesn't doesn't have a piece on the target square but still needs a captures value
    Piece.pawn: 1,
    Piece.knight: 3,
    Piece.bishop: 3,
    Piece.rook: 4,
    Piece.queen: 5,
    Piece.king: 6,
  };

  List<Move> orderMoves(Board board, List<Move> moves) {
    return moves..sort((a, b) => calculateMoveScore(board, b).compareTo(calculateMoveScore(board, a)));
  }

  int calculateMoveScore(Board board, Move move) {
    int score = 0;
    // If promotion?
    score += move.promotingPiece() * 10;

    // Check for captures and favour pawns taking queens
    int movingPiece = board.position[move.startingSquare];
    int capturedPiece = board.position[move.targetSquare];

    if (capturedPiece != Piece.none) {
      score += (pieceValues[Piece.type(capturedPiece)]! * 10 - pieceValues[Piece.type(movingPiece)]!);
    }

    return score;
  }
}
