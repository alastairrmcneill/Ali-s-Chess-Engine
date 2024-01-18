import 'package:flutter/material.dart';

class Piece {
  static const int none = 0;
  static const int king = 1;
  static const int pawn = 2;
  static const int knight = 3;
  static const int bishop = 4;
  static const int rook = 5;
  static const int queen = 6;

  static const int white = 0;
  static const int black = 8;

  // Pieces using bitwise OR
  static const int whiteKing = king | white;
  static const int whitePawn = pawn | white;
  static const int whiteKnight = knight | white;
  static const int whiteBishop = bishop | white;
  static const int whiteRook = rook | white;
  static const int whiteQueen = queen | white;
  static const int blackKing = king | black;
  static const int blackPawn = pawn | black;
  static const int blackKnight = knight | black;
  static const int blackBishop = bishop | black;
  static const int blackRook = rook | black;
  static const int blackQueen = queen | black;

  // Piece list
  static const int maxPieceIndex = blackQueen;
  static const List<int> pieceList = [
    whiteKing,
    whitePawn,
    whiteKnight,
    whiteBishop,
    whiteRook,
    whiteQueen,
    blackKing,
    blackPawn,
    blackKnight,
    blackBishop,
    blackRook,
    blackQueen
  ];

  // Masks
  static const int typeMask = 7;
  static const int colorMask = 1 << 3; // 0b1000

  static bool isColor(int piece, int color) {
    return (piece & colorMask) == color && piece != 0;
  }

  static int color(int piece) {
    return piece & colorMask;
  }

  static int type(int piece) {
    return piece & typeMask;
  }

  static bool isQueenOrBishop(int piece) {
    int pieceType = Piece.type(piece);
    return (pieceType == queen || pieceType == bishop);
  }

  static bool isQueenOrRook(int piece) {
    int pieceType = Piece.type(piece);
    return (pieceType == queen || pieceType == rook);
  }

  static Widget getImg(int piece) {
    String imgString = "";
    if (isColor(piece, white)) {
      imgString += "w";
    } else {
      imgString += "b";
    }

    switch (type(piece)) {
      case 1:
        imgString += "k";
        break;
      case 2:
        imgString += "p";
        break;
      case 3:
        imgString += "n";
        break;
      case 4:
        imgString += "b";
        break;
      case 5:
        imgString += "r";
        break;
      case 6:
        imgString += "q";
        break;
      default:
        imgString += "0";
        break;
    }

    return Image.asset("assets/$imgString.png");
  }

  static String print(int piece) {
    String string = "";
    switch (type(piece)) {
      case 1:
        string = "k";
        break;
      case 2:
        string = "p";
        break;
      case 3:
        string = "n";
        break;
      case 4:
        string = "b";
        break;
      case 5:
        string = "r";
        break;
      case 6:
        string = "q";
        break;
      default:
        string = "0";
        break;
    }

    if (color(piece) == Piece.white) {
      string.toUpperCase();
    }
    return string;
  }
}
