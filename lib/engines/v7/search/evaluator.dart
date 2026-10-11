import 'dart:math';

import 'package:ace/engines/v7/core/board.dart';
import 'package:ace/engines/v7/core/piece.dart';
import 'package:ace/engines/v7/search/piece_square_tables.dart';

class Evaluator {
  // index 0 = white, 1 = black
  List<int> pawns = [0, 0];
  List<int> knights = [0, 0];
  List<int> bishops = [0, 0];
  List<int> rooks = [0, 0];
  List<int> queens = [0, 0];
  List<int> lightBishops = [0, 0];
  List<int> darkBishops = [0, 0];
  int whiteKing = -1;
  int blackKing = -1;
  static const List<int> cmd = [
    // Central Manhattan Distance for king end games
    6, 5, 4, 3, 3, 4, 5, 6,
    5, 4, 3, 2, 2, 3, 4, 5,
    4, 3, 2, 1, 1, 2, 3, 4,
    3, 2, 1, 0, 0, 1, 2, 3,
    3, 2, 1, 0, 0, 1, 2, 3,
    4, 3, 2, 1, 1, 2, 3, 4,
    5, 4, 3, 2, 2, 3, 4, 5,
    6, 5, 4, 3, 3, 4, 5, 6,
  ];

  final pieceValues = {
    Piece.pawn: 100,
    Piece.rook: 500,
    Piece.knight: 320,
    Piece.bishop: 330,
    Piece.queen: 900,
    Piece.king: 10000,
  };

  int evaluate(Board board) {
    int whiteMaterialScore = 0;
    int blackMaterialScore = 0;
    int midgamePhase = 0;
    int mgScore = 0;
    int egScore = 0;
    // index 0 = white, 1 = black
    pawns = [0, 0];
    knights = [0, 0];
    bishops = [0, 0];
    rooks = [0, 0];
    queens = [0, 0];
    lightBishops = [0, 0];
    darkBishops = [0, 0];
    whiteKing = -1;
    blackKing = -1;

    for (var i = 0; i < board.position.length; i++) {
      final piece = board.position[i];

      if (piece == Piece.none) continue;

      final color = Piece.isColor(piece, Piece.white) ? 0 : 1;

      switch (Piece.type(piece)) {
        case Piece.pawn:
          pawns[color]++;

          if (color == 0) {
            mgScore += PieceSquareTables.pawnMg[i];
            egScore += PieceSquareTables.pawnMg[i];
          } else {
            mgScore -= PieceSquareTables.pawnMg[i ^ 56];
            egScore -= PieceSquareTables.pawnMg[i ^ 56];
          }

          break;
        case Piece.knight:
          knights[color]++;
          if (color == 0) {
            mgScore += PieceSquareTables.knightMg[i];
            egScore += PieceSquareTables.knightMg[i];
          } else {
            mgScore -= PieceSquareTables.knightMg[i ^ 56];
            egScore -= PieceSquareTables.knightMg[i ^ 56];
          }
          break;
        case Piece.bishop:
          bishops[color]++;
          ((i ~/ 8 + i % 8) % 2 == 0 ? lightBishops : darkBishops)[color]++;
          if (color == 0) {
            mgScore += PieceSquareTables.bishopMg[i];
            egScore += PieceSquareTables.bishopMg[i];
          } else {
            mgScore -= PieceSquareTables.bishopMg[i ^ 56];
            egScore -= PieceSquareTables.bishopMg[i ^ 56];
          }
          break;
        case Piece.rook:
          rooks[color]++;
          if (color == 0) {
            mgScore += PieceSquareTables.rookMg[i];
            egScore += PieceSquareTables.rookMg[i];
          } else {
            mgScore -= PieceSquareTables.rookMg[i ^ 56];
            egScore -= PieceSquareTables.rookMg[i ^ 56];
          }
          break;
        case Piece.queen:
          queens[color]++;
          if (color == 0) {
            mgScore += PieceSquareTables.queenMg[i];
            egScore += PieceSquareTables.queenMg[i];
          } else {
            mgScore -= PieceSquareTables.queenMg[i ^ 56];
            egScore -= PieceSquareTables.queenMg[i ^ 56];
          }
          break;
        case Piece.king:
          if (color == 0) {
            whiteKing = i;
            mgScore += PieceSquareTables.kingMg[i];
            egScore += PieceSquareTables.kingEg[i];
          } else {
            blackKing = i;
            mgScore -= PieceSquareTables.kingMg[i ^ 56];
            egScore -= PieceSquareTables.kingEg[i ^ 56];
          }
          break;
      }

      // Count material

      if (Piece.isColor(piece, Piece.white)) {
        whiteMaterialScore += pieceValues[Piece.type(piece)]!;
      } else {
        blackMaterialScore += pieceValues[Piece.type(piece)]!;
      }
    }

    midgamePhase = min(calculatePhase(), 24);

    final noHeavy = pawns[0] + pawns[1] + rooks[0] + rooks[1] + queens[0] + queens[1] == 0;
    if (noHeavy && knights[0] + bishops[0] <= 1 && knights[1] + bishops[1] <= 1) return 0;

    int? strong;
    int mopUpEval = 0;

    if (isBareKing(0) && hasMatingMaterial(1)) strong = 1;
    if (isBareKing(1) && hasMatingMaterial(0)) strong = 0;
    if (strong != null) {
      final mopUpScore = mopUp(
        strong,
        strong == 0 ? whiteKing : blackKing,
        strong == 0 ? blackKing : whiteKing,
      );
      // White's point of view, like whiteMaterialScore - blackMaterialScore. The side-to-move flip happens once, at the return.
      mopUpEval = strong == 0 ? mopUpScore : -mopUpScore;

      final score = whiteMaterialScore - blackMaterialScore + mopUpEval;
      return board.whiteToPlay ? score : -score;
    }

    int pieceSquareTableScore = ((mgScore * midgamePhase + egScore * (24 - midgamePhase)) ~/ 24);

    int evaluation = whiteMaterialScore - blackMaterialScore + pieceSquareTableScore;

    return board.whiteToPlay ? evaluation : -evaluation;
  }

  int calculatePhase() {
    int phase = 0;
    phase += (knights[0] + knights[1]) * 1;
    phase += (bishops[0] + bishops[1]) * 1;
    phase += (rooks[0] + rooks[1]) * 2;
    phase += (queens[0] + queens[1]) * 4;
    return phase;
  }

  int mopUp(int strong, int strongKing, int weakKing) {
    int score = 0;

    final isKBNK = bishops[strong] == 1 && knights[strong] == 1 && rooks[strong] == 0 && queens[strong] == 0;

    if (isKBNK) {
      // Determine which corner the weak king should be pushed towards based on the bishop's color
      final bishopIsLight = lightBishops[strong] == 1;

      final cornerA = bishopIsLight ? 0 : 56; // a8 / a1
      final cornerB = bishopIsLight ? 63 : 7; // h1 / h8

      final distance = min(manhattanDistance(weakKing, cornerA), manhattanDistance(weakKing, cornerB));

      score += (14 - distance) * 10;
    } else {
      // Use CMD to promote pushing the weak king into a corner
      score += centerManhattanDistance(weakKing) * 10;
    }

    // Use Chebyshev distance to promote strong king moving towards weak king
    score += (7 - chebyshevDistance(strongKing, weakKing)) * 5;

    return score;
  }

  bool isBareKing(int c) {
    return pawns[c] == 0 && knights[c] == 0 && bishops[c] == 0 && rooks[c] == 0 && queens[c] == 0;
  }

  bool hasMatingMaterial(int c) {
    if (pawns[c] != 0) return false;
    if (queens[c] > 0 || rooks[c] > 0) return true;
    if (knights[c] > 0 && bishops[c] > 0) return true;
    if (lightBishops[c] > 0 && darkBishops[c] > 0) return true;
    return false;
  }

  int manhattanDistance(int squareA, int squareB) {
    final fileA = squareA % 8;
    final rankA = squareA ~/ 8;
    final fileB = squareB % 8;
    final rankB = squareB ~/ 8;

    return (fileA - fileB).abs() + (rankA - rankB).abs();
  }

  int chebyshevDistance(int squareA, int squareB) {
    final fileA = squareA % 8;
    final rankA = squareA ~/ 8;
    final fileB = squareB % 8;
    final rankB = squareB ~/ 8;

    return max((fileA - fileB).abs(), (rankA - rankB).abs());
  }

  int centerManhattanDistance(int square) {
    return cmd[square];
  }
}
