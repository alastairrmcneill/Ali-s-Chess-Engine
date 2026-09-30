import 'package:ace/chess_core/board_helper.dart';
import 'package:ace/chess_core/fen.dart';
import 'package:ace/chess_core/piece.dart';
import 'package:ace/components/piece_image.dart';
import 'package:flutter/material.dart';

/// Read-only board for a FEN, with the last move highlighted. Uses the same colours as the play screen.
class BoardView extends StatelessWidget {
  final String fen;
  final String? lastMoveUci;

  const BoardView({super.key, required this.fen, this.lastMoveUci});

  static const Color _light = Color.fromRGBO(238, 238, 213, 1);
  static const Color _dark = Color.fromRGBO(124, 149, 93, 1);
  static const Color _lightHighlight = Color.fromARGB(255, 241, 241, 150);
  static const Color _darkHighlight = Color.fromARGB(255, 183, 215, 57);

  @override
  Widget build(BuildContext context) {
    FenPosition position = FenPosition.parse(fen);
    Set<int> highlighted = {};
    if (lastMoveUci != null && lastMoveUci!.length >= 4) {
      highlighted.add(BoardHelper.squareIndex(lastMoveUci!.substring(0, 2)));
      highlighted.add(BoardHelper.squareIndex(lastMoveUci!.substring(2, 4)));
    }

    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: 64,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
        itemBuilder: (context, index) {
          bool isLight = (BoardHelper.getRankFromIndex(index) + BoardHelper.getFileFromIndex(index)) % 2 == 0;
          bool isHighlighted = highlighted.contains(index);
          String? piece = position.squares[index];
          return Container(
            color: isHighlighted ? (isLight ? _lightHighlight : _darkHighlight) : (isLight ? _light : _dark),
            child: piece == null ? null : pieceImage(Piece.fromFenChar(piece)),
          );
        },
      ),
    );
  }
}
