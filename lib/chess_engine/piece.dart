import 'package:flutter/material.dart';

class Piece {
  static const int none = 0;
  static const int king = 1;
  static const int pawn = 2;
  static const int knight = 3;
  static const int bishop = 4;
  static const int rook = 5;
  static const int queen = 6;

  static const int white = 8;
  static const int black = 16;

  static const int typeMask = 7;
  static const int colorMask = 1 << 3 | 1 << 4; // 0b00011000

  static bool isColor(int piece, int color) {
    return (piece & colorMask) == color;
  }

  static int color(int piece) {
    return piece & colorMask;
  }

  static int pieceType(int piece) {
    return piece & typeMask;
  }

  static bool isQueenOrBishop(int piece) {
    int pieceType = Piece.pieceType(piece);

    return (pieceType == queen || pieceType == bishop);
  }

  static bool isQueenOrRook(int piece) {
    int pieceType = Piece.pieceType(piece);

    return (pieceType == queen || pieceType == rook);
  }

  static Widget getImg(int piece) {
    String imgString = "";
    if (isColor(piece, white)) {
      imgString += "w";
    } else {
      imgString += "b";
    }

    switch (pieceType(piece)) {
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

    return Image.asset("assets/${imgString}.png");
  }

  static String print(int piece) {
    String string = "";
    switch (pieceType(piece)) {
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
