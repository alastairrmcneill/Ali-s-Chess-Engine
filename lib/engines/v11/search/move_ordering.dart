import 'package:ace/engines/v11/core/board.dart';
import 'package:ace/engines/v11/core/move.dart';
import 'package:ace/engines/v11/core/piece.dart';

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

  List<Move> orderMoves(Board board, List<Move> moves, {Move ttMove = Move.invalid}) {
    return moves
      ..sort((a, b) {
        return calculateMoveScore(board, b, ttMove).compareTo(calculateMoveScore(board, a, ttMove));
      });
  }

  int calculateMoveScore(Board board, Move move, Move ttMove) {
    int score = 0;
    if (move == ttMove) return 10000;
    // If promotion?
    score += move.promotingPiece() * 10;

    // Check for captures and favour pawns taking queens
    int movingPiece = board.position[move.from];
    int capturedPiece = board.position[move.to];

    if (capturedPiece != Piece.none) {
      score += (pieceValues[Piece.type(capturedPiece)]! * 10 - pieceValues[Piece.type(movingPiece)]!);
    }

    return score;
  }
}
