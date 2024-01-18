import 'package:ace/chess_engine/core/piece.dart';
import 'package:flutter/material.dart';

class Square extends StatelessWidget {
  final int index;
  final bool isWhite;
  final int piece;
  final bool isSelected;
  final bool isDraggable;
  final bool isSquareValid;
  final bool isLastMove;
  final Function() onTap;
  final Function() onDragStarted;
  final Function() onDragComplete;
  final Function(Velocity, Offset) onDragableCancelled;

  const Square({
    super.key,
    required this.index,
    required this.isWhite,
    required this.piece,
    required this.isSelected,
    required this.isDraggable,
    required this.isSquareValid,
    required this.isLastMove,
    required this.onTap,
    required this.onDragStarted,
    required this.onDragComplete,
    required this.onDragableCancelled,
  });

  final Color lightSquareColor = const Color.fromRGBO(238, 238, 213, 1);
  final Color darkSquareColor = const Color.fromRGBO(124, 149, 93, 1);
  final Color lightSquareSelectedColor = const Color.fromARGB(255, 241, 241, 150);
  final Color darkSquareSelectedColor = const Color.fromARGB(255, 183, 215, 57);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected || isLastMove
              ? isWhite
                  ? lightSquareSelectedColor
                  : darkSquareSelectedColor
              : isWhite
                  ? lightSquareColor
                  : darkSquareColor,
        ),
        child: isDraggable
            ? Draggable<int>(
                data: piece,
                onDraggableCanceled: onDragableCancelled,
                feedback: SizedBox(
                  width: MediaQuery.of(context).size.width / 8,
                  height: MediaQuery.of(context).size.width / 8,
                  child: piece == 0 ? null : Piece.getImg(piece),
                ),
                onDragStarted: onDragStarted,
                childWhenDragging: Container(
                  decoration: BoxDecoration(
                    color: isWhite ? lightSquareSelectedColor : darkSquareSelectedColor,
                  ),
                ),
                onDragCompleted: onDragComplete,
                child: Center(
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width / 8,
                    height: MediaQuery.of(context).size.width / 8,
                    child: piece == 0 ? const SizedBox() : Piece.getImg(piece),
                  ),
                ),
              )
            : Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width / 8,
                  height: MediaQuery.of(context).size.width / 8,
                  child: Stack(
                    children: [
                      Text(index.toString()),
                      piece == 0
                          ? isSquareValid
                              ? Stack(
                                  children: [
                                    Text(index.toString()),
                                    Container(
                                      margin: const EdgeInsets.all(15),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox()
                          : Stack(
                              children: [
                                Text(index.toString()),
                                Piece.getImg(piece),
                                isSquareValid
                                    ? Container(
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(100),
                                          border: Border.all(width: 5, color: Colors.grey.withOpacity(0.7)),
                                        ),
                                      )
                                    : const SizedBox(),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
