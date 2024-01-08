import 'dart:math';

import 'package:ace/chess_engine/ai/piece_square_tables.dart';
import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/piece.dart';
import 'package:ace/chess_engine/precompute_data.dart';

class Evaluation {
  PrecomputeData precomputeData = PrecomputeData();
  PieceSquareTables pieceSquareTables = PieceSquareTables();

  final int pawnValue = 100;
  final int knightValue = 300;
  final int bishopValue = 300;
  final int rookValue = 500;
  final int queenValue = 900;
  final int endgameMaterialStart = 500 * 2 + 300 + 300;

  late Board board;
  late List<int> whitePawnIndexes;
  late List<int> blackPawnIndexes;
  late List<int> whiteKnightIndexes;
  late List<int> blackKnightIndexes;
  late List<int> whiteBishopIndexes;
  late List<int> blackBishopIndexes;
  late List<int> whiteRookIndexes;
  late List<int> blackRookIndexes;
  late List<int> whiteQueenIndexes;
  late List<int> blackQueenIndexes;
  late int blackKingIndex;
  late int whiteKingIndex;

  int evaluate(Board board) {
    this.board = board;
    init();
    int whiteEval = 0;
    int blackEval = 0;

    int whiteMaterial = whitePawnIndexes.length * pawnValue +
        whiteKnightIndexes.length * knightValue +
        whiteBishopIndexes.length * bishopValue +
        whiteRookIndexes.length * rookValue +
        whiteQueenIndexes.length * queenValue;
    int blackMaterial = blackPawnIndexes.length * pawnValue +
        blackKnightIndexes.length * knightValue +
        blackBishopIndexes.length * bishopValue +
        blackRookIndexes.length * rookValue +
        blackQueenIndexes.length * queenValue;

    whiteEval += whiteMaterial;
    blackEval += blackMaterial;

    // Check what phase of the game we are in
    double whiteEndGameWeight = endGameWeight(whiteMaterial - whitePawnIndexes.length * pawnValue);
    double blackEndGameWeight = endGameWeight(blackMaterial - blackPawnIndexes.length * pawnValue);

    // Piece Square Tables
    for (int index in whitePawnIndexes) {
      whiteEval += ((1 - whiteEndGameWeight) * pieceSquareTables.whitePawnsEarly[index] +
              (whiteEndGameWeight) * pieceSquareTables.whitePawnsEnd[index])
          .toInt();
    }
    for (int index in whiteKnightIndexes) {
      whiteEval += pieceSquareTables.whiteKnights[index];
    }
    for (int index in whiteBishopIndexes) {
      whiteEval += pieceSquareTables.whiteBishops[index];
    }
    for (int index in whiteRookIndexes) {
      whiteEval += pieceSquareTables.whiteRooks[index];
    }
    for (int index in whiteQueenIndexes) {
      whiteEval += pieceSquareTables.whiteQueens[index];
    }
    whiteEval += ((1 - whiteEndGameWeight) * pieceSquareTables.whiteKingStart[whiteKingIndex] +
            (whiteEndGameWeight) * pieceSquareTables.whiteKingEnd[whiteKingIndex])
        .toInt();

    for (int index in blackPawnIndexes) {
      blackEval += ((1 - blackEndGameWeight) * pieceSquareTables.blackPawnsEarly[index] +
              (blackEndGameWeight) * pieceSquareTables.blackPawnsEnd[index])
          .toInt();
    }
    for (int index in blackKnightIndexes) {
      blackEval += pieceSquareTables.blackKnights[index];
    }
    for (int index in blackBishopIndexes) {
      blackEval += pieceSquareTables.blackBishops[index];
    }
    for (int index in blackRookIndexes) {
      blackEval += pieceSquareTables.blackRooks[index];
    }
    for (int index in blackQueenIndexes) {
      blackEval += pieceSquareTables.blackQueens[index];
    }
    blackEval += ((1 - blackEndGameWeight) * pieceSquareTables.blackKingStart[blackKingIndex] +
            (blackEndGameWeight) * pieceSquareTables.blackKingEnd[blackKingIndex])
        .toInt();

    // The further from the center the worse it is for your king later in the end game
    whiteEval += mopUp(whiteMaterial, blackMaterial, whiteKingIndex, blackKingIndex, blackEndGameWeight);
    blackEval += mopUp(blackMaterial, whiteMaterial, blackKingIndex, whiteKingIndex, whiteEndGameWeight);

    int perspective = board.whiteToPlay ? 1 : -1;
    return perspective * (whiteEval - blackEval);
  }

  init() {
    whitePawnIndexes = [];
    blackPawnIndexes = [];
    blackKnightIndexes = [];
    whiteKnightIndexes = [];
    whiteBishopIndexes = [];
    blackBishopIndexes = [];
    whiteRookIndexes = [];
    blackRookIndexes = [];
    whiteQueenIndexes = [];
    blackQueenIndexes = [];
    whiteKingIndex = -1;
    blackKingIndex = -1;

    findPieces();
  }

  void findPieces() {
    for (var index = 0; index < board.position.length; index++) {
      int piece = board.position[index];
      int pieceType = Piece.pieceType(piece);

      switch (pieceType) {
        case Piece.pawn:
          Piece.isColor(piece, Piece.white) ? whitePawnIndexes.add(index) : blackPawnIndexes.add(index);
          break;
        case Piece.knight:
          Piece.isColor(piece, Piece.white) ? whiteKnightIndexes.add(index) : blackKnightIndexes.add(index);
          break;
        case Piece.bishop:
          Piece.isColor(piece, Piece.white) ? whiteBishopIndexes.add(index) : blackBishopIndexes.add(index);
          break;
        case Piece.rook:
          Piece.isColor(piece, Piece.white) ? whiteRookIndexes.add(index) : blackRookIndexes.add(index);
          break;
        case Piece.queen:
          Piece.isColor(piece, Piece.white) ? whiteQueenIndexes.add(index) : blackQueenIndexes.add(index);
          break;
        case Piece.king:
          Piece.isColor(piece, Piece.white) ? whiteKingIndex = index : blackKingIndex = index;
          break;
        default:
          break;
      }
    }
  }

  double endGameWeight(int materialCountWithoutPawns) {
    double multiplier = 1 / endgameMaterialStart;
    return 1 - min(1, materialCountWithoutPawns * multiplier);
  }

  int kingOrthogonalDistanceApart(int friendlyKingIndex, int opponentKingIndex) {
    int files = (friendlyKingIndex % 8 - opponentKingIndex % 8).abs();
    int ranks = (friendlyKingIndex ~/ 8 - opponentKingIndex ~/ 8).abs();

    return files + ranks;
  }

  int mopUp(
    int friendlyMaterial,
    int oppponentMaterial,
    int friendlyKingIndex,
    int opponentKingIndex,
    double endgameWeight,
  ) {
    int mopUpScore = 0;
    // Only apply these scores if I'm winning and in the end game
    if (friendlyMaterial > oppponentMaterial + 2 * pawnValue && endgameWeight > 0) {
      // If we are winning then get rewarded for opponent being more to the sides and corner of the board
      mopUpScore += precomputeData.cmd[opponentKingIndex] * 10;

      // If we are winning then we want the kings to be close together so rewards for that too
      mopUpScore += (14 - kingOrthogonalDistanceApart(friendlyKingIndex, opponentKingIndex)) * 4;

      return (mopUpScore * endgameWeight).toInt();
    }
    return 0;
  }
}
