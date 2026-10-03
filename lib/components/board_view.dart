import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/components/piece_image.dart';
import 'package:ace/components/square.dart';
import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BoardView extends StatelessWidget {
  const BoardView({super.key});

  Future<void> _attemptMove(BuildContext context, GameProvider game, int from, int to) async {
    final moves = game.movesBetween(from, to);
    if (moves.isEmpty) return;

    Move? chosen = moves.first;
    if (moves.length > 1) {
      chosen = await _pickPromotion(context, game, moves);
    }
    if (chosen == null) {
      game.clearSelection();
      return;
    }
    game.playHumanMove(chosen);
  }

  Future<Move?> _pickPromotion(BuildContext context, GameProvider game, List<Move> moves) {
    // Show queen, rook, bishop, knight in that order.
    const order = [1, 3, 4, 2];
    final sorted = [...moves]..sort((a, b) => order.indexOf(a.promotion).compareTo(order.indexOf(b.promotion)));

    return showDialog<Move>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Promote to'),
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final move in sorted)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(move),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: pieceImage(move.promotingPiece() | game.playerColor),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final flipped = !game.playerIsWhite;
    final last = game.lastMove;

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide / 8;

          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                for (int row = 0; row < 8; row++)
                  Row(
                    children: [
                      for (int col = 0; col < 8; col++)
                        _buildSquare(context, game, flipped ? 63 - (row * 8 + col) : row * 8 + col, row, col, size, last),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSquare(BuildContext context, GameProvider game, int index, int row, int col, double size, Move? last) {
    final rank = BoardHelper.getRankFromIndex(index);
    final file = BoardHelper.getFileFromIndex(index);

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => game.movesBetween(details.data, index).isNotEmpty,
      onAcceptWithDetails: (details) => _attemptMove(context, game, details.data, index),
      builder: (context, candidates, rejected) => Square(
        index: index,
        size: size,
        isLight: (rank + file) % 2 == 0,
        piece: game.position[index],
        isSelected: index == game.selectedIndex,
        isLastMove: last != null && (index == last.startingSquare || index == last.targetSquare),
        isMoveTarget: game.isTargetOfSelected(index),
        isDraggable: game.canPickUp(index),
        rankLabel: col == 0 ? BoardHelper.squareName(index)[1] : null,
        fileLabel: row == 7 ? BoardHelper.squareName(index)[0] : null,
        onDragStarted: () => game.pickUp(index),
        onTap: () {
          final from = game.selectedIndex;
          if (from != null && game.movesBetween(from, index).isNotEmpty) {
            _attemptMove(context, game, from, index);
          } else {
            game.select(index);
          }
        },
      ),
    );
  }
}
