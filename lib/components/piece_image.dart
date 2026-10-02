import 'package:flutter/material.dart';
import 'package:ace/chess_core/notation/piece.dart';

Widget pieceImage(int piece) {
  String imgString = "";
  if (Piece.isColor(piece, Piece.white)) {
    imgString += "w";
  } else {
    imgString += "b";
  }

  switch (Piece.type(piece)) {
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
