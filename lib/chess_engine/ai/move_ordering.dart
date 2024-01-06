import 'package:ace/chess_engine/ai/evaluation.dart';
import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/piece.dart';

class MoveOrdering {
  Evaluation evaluation = Evaluation();
  List<Move> orderMoves(Board board, List<Move> moves, Move bestMove) {
    moves.sort(
      (a, b) => calculateMoveScore(board, b, bestMove).compareTo(calculateMoveScore(board, a, bestMove)),
    );

    return moves;
  }

  int calculateMoveScore(Board board, Move move, Move bestMove) {
    if (move.isSameAs(bestMove)) return 1000000000000;
    int score = 0;
    int movedPiece = board.position[move.startingSquare];
    int capturedPiece = board.position[move.targetSquare];

    // If low value piece captures high value piece then give this a higher score
    // If high value piece captures low value piece then give this a lower score but still above 0
    // If no captures then no score
    if (capturedPiece != Piece.none) {
      score += 10 * getPieceValue(capturedPiece) - getPieceValue(movedPiece);
    }

    // If promotion happens 2 and 4 give same, 1 is queen, 3 is rook
    switch (move.promotion) {
      case 1:
        score += evaluation.queenValue;
        break;
      case 2:
        score += evaluation.knightValue;
        break;
      case 3:
        score += evaluation.rookValue;
      case 4:
        score += evaluation.bishopValue;
      default:
        break;
    }

    return score;
  }

  int getPieceValue(int piece) {
    switch (Piece.pieceType(piece)) {
      case Piece.pawn:
        return evaluation.pawnValue;
      case Piece.knight:
        return evaluation.knightValue;
      case Piece.bishop:
        return evaluation.bishopValue;
      case Piece.rook:
        return evaluation.rookValue;
      case Piece.queen:
        return evaluation.queenValue;
      default:
        return 0;
    }
  }
}
