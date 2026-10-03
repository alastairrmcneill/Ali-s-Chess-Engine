import 'package:ace/components/piece_image.dart';
import 'package:ace/theme/app_theme.dart';
import 'package:flutter/material.dart';

class Square extends StatelessWidget {
  final int index;
  final double size;
  final bool isLight;
  final int piece;
  final bool isSelected;
  final bool isLastMove;
  final bool isMoveTarget;
  final bool isDraggable;
  final String? fileLabel;
  final String? rankLabel;
  final VoidCallback onTap;
  final VoidCallback onDragStarted;

  const Square({
    super.key,
    required this.index,
    required this.size,
    required this.isLight,
    required this.piece,
    required this.isSelected,
    required this.isLastMove,
    required this.isMoveTarget,
    required this.isDraggable,
    required this.onTap,
    required this.onDragStarted,
    this.fileLabel,
    this.rankLabel,
  });

  @override
  Widget build(BuildContext context) {
    final base = isLight ? AppTheme.lightSquare : AppTheme.darkSquare;
    final labelStyle = TextStyle(
      fontSize: size * 0.18,
      fontWeight: FontWeight.w600,
      color: isLight ? AppTheme.darkSquare : AppTheme.lightSquare,
    );

    final pieceWidget = SizedBox(width: size, height: size, child: pieceImage(piece));

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: base)),
            if (isSelected || isLastMove) const Positioned.fill(child: ColoredBox(color: AppTheme.highlight)),
            if (rankLabel != null)
              Positioned(left: size * 0.05, top: size * 0.03, child: Text(rankLabel!, style: labelStyle)),
            if (fileLabel != null)
              Positioned(right: size * 0.06, bottom: size * 0.02, child: Text(fileLabel!, style: labelStyle)),
            if (isMoveTarget && piece == 0)
              Center(
                child: Container(
                  width: size * 0.28,
                  height: size * 0.28,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.moveHint),
                ),
              ),
            if (isMoveTarget && piece != 0)
              Positioned.fill(
                child: Container(
                  margin: EdgeInsets.all(size * 0.04),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(width: size * 0.07, color: AppTheme.moveHint),
                  ),
                ),
              ),
            if (piece != 0)
              Positioned.fill(
                child: isDraggable
                    ? Draggable<int>(
                        data: index,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        onDragStarted: onDragStarted,
                        feedback: Transform.translate(
                          offset: Offset(-size * 0.6, -size * 0.6),
                          child: SizedBox(width: size * 1.2, height: size * 1.2, child: pieceImage(piece)),
                        ),
                        childWhenDragging: const SizedBox.shrink(),
                        child: pieceWidget,
                      )
                    : pieceWidget,
              ),
          ],
        ),
      ),
    );
  }
}
