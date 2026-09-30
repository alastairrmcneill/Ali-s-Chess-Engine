import 'package:ace/chess_core/board_helper.dart';
import 'package:ace/chess_core/piece.dart';

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

  /// UCI notation, e.g. "e2e4" or "e7e8q"
  String toChessNotation() {
    String promotionLetter = promotion == 0 ? "" : " qnrb"[promotion];
    return "${BoardHelper.squareName(startingSquare)}${BoardHelper.squareName(targetSquare)}$promotionLetter";
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
