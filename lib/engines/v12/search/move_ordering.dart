import 'dart:typed_data';

import 'package:ace/engines/v12/core/board.dart';
import 'package:ace/engines/v12/core/move.dart';
import 'package:ace/engines/v12/core/piece.dart';

class MoveOrdering {
  static const List<int> pieceValues = [1, 6, 1, 3, 3, 4, 5];

  void scoreMoves(Board board, List<Move> moves, Int32List scores, {Move ttMove = Move.invalid}) {
    for (int i = 0; i < moves.length; i++) {
      scores[i] = _calculateMoveScore(board, moves[i], ttMove);
    }
  }

  void pickBest(List<Move> moves, Int32List scores, int startingIndex) {
    int bestIndex = startingIndex;
    for (int i = startingIndex + 1; i < moves.length; i++) {
      if (scores[i] > scores[bestIndex]) bestIndex = i;
    }
    if (bestIndex != startingIndex) {
      final m = moves[startingIndex];
      moves[startingIndex] = moves[bestIndex];
      moves[bestIndex] = m;
      final s = scores[startingIndex];
      scores[startingIndex] = scores[bestIndex];
      scores[bestIndex] = s;
    }
  }

  List<Move> orderMoves(Board board, List<Move> moves, {Move ttMove = Move.invalid}) {
    return moves
      ..sort((a, b) {
        return _calculateMoveScore(board, b, ttMove).compareTo(_calculateMoveScore(board, a, ttMove));
      });
  }

  int _calculateMoveScore(Board board, Move move, Move ttMove) {
    int score = 0;
    if (move == ttMove) return 10000;
    // If promotion?
    score += move.promotingPiece() * 10;

    // Check for captures and favour pawns taking queens
    int movingPiece = board.position[move.from];
    int capturedPiece = board.position[move.to];

    if (capturedPiece != Piece.none) {
      score += (pieceValues[Piece.type(capturedPiece)] * 10 - pieceValues[Piece.type(movingPiece)]);
    }

    return score;
  }
}
