import 'package:ace/chess_engine/helpers/board_helper.dart';
import 'package:ace/chess_engine/core/piece.dart';

class Move {
  final int startingSquare;
  final int targetSquare;
  final bool enPassantCapture;
  final bool pawnTwoForward;
  final int promotion;
  final bool castling;

  Move({
    required this.startingSquare,
    required this.targetSquare,
    this.enPassantCapture = false,
    this.pawnTwoForward = false,
    this.promotion = 0,
    this.castling = false,
  });

  static Move get invalid {
    return Move(startingSquare: -1, targetSquare: -1);
  }

  int promotingPiece() {
    switch (promotion) {
      case 1:
        return Piece.queen;
      case 2:
        return Piece.knight;
      case 3:
        return Piece.rook;
      case 4:
        return Piece.bishop;
      default:
        return Piece.none;
    }
  }

  String toChessNotation() {
    String files = "abcdefgh";

    int startingFile = BoardHelper.getFileFromIndex(startingSquare);
    int startingRank = 8 - BoardHelper.getRankFromIndex(startingSquare);
    int targetFile = BoardHelper.getFileFromIndex(targetSquare);
    int targetRank = 8 - BoardHelper.getRankFromIndex(targetSquare);

    return "${files[startingFile]}$startingRank${files[targetFile]}$targetRank";
  }

  bool isSameAs(Move checkingMove) {
    return startingSquare == checkingMove.startingSquare &&
        targetSquare == checkingMove.targetSquare &&
        enPassantCapture == checkingMove.enPassantCapture &&
        pawnTwoForward == checkingMove.pawnTwoForward &&
        promotion == checkingMove.promotion &&
        castling == checkingMove.castling;
  }

  @override
  String toString() {
    return "From: $startingSquare To: $targetSquare";
  }
}
