import 'package:ace/engines/v3/core/board.dart';
import 'package:ace/engines/v3/core/move.dart';
import 'package:ace/engines/v3/core/piece.dart';

class MoveOrdering {
  List<Move> orderMoves(Board board, List<Move> moves) {
    return moves..sort((a, b) => calculateMoveScore(board, b).compareTo(calculateMoveScore(board, a)));
  }

  int calculateMoveScore(Board board, Move move) {
    int score = 0;
    // If promotion?
    score += move.promotingPiece();

    // Check for captures and favour pawns taking queens
    int movingPiece = board.position[move.startingSquare];
    int capturedPiece = board.position[move.targetSquare];

    if (capturedPiece != Piece.none) {
      score += (capturedPiece - movingPiece);
    }

    return score;
  }
}
