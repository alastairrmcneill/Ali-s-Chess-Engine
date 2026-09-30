import 'package:ace/chess_core/piece.dart';
import 'package:flutter/material.dart';

/// Image for a piece from assets/, e.g. assets/wn.png for a white knight
Widget pieceImage(int piece) {
  String color = Piece.isColor(piece, Piece.white) ? "w" : "b";
  return Image.asset("assets/$color${Piece.toFenChar(piece).toLowerCase()}.png");
}
