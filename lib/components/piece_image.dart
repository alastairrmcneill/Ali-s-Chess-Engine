import 'package:ace/chess_core/notation/piece.dart';
import 'package:flutter/material.dart';

const _pieceLetters = {
  Piece.king: 'k',
  Piece.pawn: 'p',
  Piece.knight: 'n',
  Piece.bishop: 'b',
  Piece.rook: 'r',
  Piece.queen: 'q',
};

Widget pieceImage(int piece) {
  final letter = _pieceLetters[Piece.type(piece)];
  if (letter == null) return const SizedBox.shrink();

  final color = Piece.isColor(piece, Piece.white) ? 'w' : 'b';
  return Image.asset('assets/$color$letter.png', gaplessPlayback: true);
}
