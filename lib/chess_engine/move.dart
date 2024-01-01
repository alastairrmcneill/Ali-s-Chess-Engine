import 'package:ace/chess_engine/piece.dart';

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

  int promotingPiece() {
    if (promotion == 1) {
      return Piece.queen;
    }
    if (promotion == 2) {
      return Piece.knight;
    }
    if (promotion == 3) {
      return Piece.rook;
    }
    if (promotion == 4) {
      return Piece.bishop;
    } else {
      return Piece.none;
    }
  }

  String toChessNotation() {
    String files = "abcdefgh";

    int startingFile = startingSquare % 8;
    int startingRank = 8 - startingSquare ~/ 8;
    int targetFile = targetSquare % 8;
    int targetRank = 8 - targetSquare ~/ 8;

    return "${files[startingFile]}$startingRank${files[targetFile]}$targetRank";
  }

  @override
  String toString() {
    return "From: $startingSquare To: $targetSquare - EnPassant $enPassantCapture, PawnTwoForward: $pawnTwoForward";
  }
}
