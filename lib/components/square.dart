import 'package:ace/chess_engine/piece.dart';
import 'package:flutter/material.dart';

class Square extends StatelessWidget {
  final bool isWhite;
  final int piece;
  final Function() onTap;

  final Function() onDragStarted;
  final Function() onDragComplete;
  final Function(Velocity, Offset) onDragableCancelled;
  final bool isSelected;
  final bool isDraggable;
  final int index;
  final bool isSquareValid;
  final bool isSquareAttacked;
  final bool isLastMove;

  const Square({
    super.key,
    required this.isWhite,
    required this.piece,
    required this.onTap,
    required this.onDragStarted,
    required this.onDragComplete,
    required this.isSelected,
    required this.isDraggable,
    required this.index,
    required this.isSquareValid,
    required this.onDragableCancelled,
    required this.isSquareAttacked,
    required this.isLastMove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected || isLastMove
              ? isWhite
                  ? const Color.fromARGB(255, 241, 241, 150)
                  : const Color.fromARGB(255, 183, 215, 57)
              : isWhite
                  ? const Color.fromRGBO(238, 238, 213, 1)
                  : const Color.fromRGBO(124, 149, 93, 1),
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
                    color: isWhite ? const Color.fromARGB(255, 241, 241, 150) : const Color.fromARGB(255, 183, 215, 57),
                  ),
                ),
                onDragCompleted: onDragComplete,
                child: Center(
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width / 8,
                    height: MediaQuery.of(context).size.width / 8,
                    child: Stack(
                      children: [
                        isSquareAttacked
                            ? Container(
                                width: MediaQuery.of(context).size.width / 8,
                                height: MediaQuery.of(context).size.width / 8,
                                color: Colors.red.withOpacity(0.2),
                              )
                            : const SizedBox(),
                        // Text(index.toString()),
                        piece == 0 ? const SizedBox() : Piece.getImg(piece),
                      ],
                    ),
                  ),
                ),
              )
            : Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width / 8,
                  height: MediaQuery.of(context).size.width / 8,
                  // child: Text(index.toString()),
                  child: Stack(
                    children: [
                      isSquareAttacked
                          ? Container(
                              width: MediaQuery.of(context).size.width / 8,
                              height: MediaQuery.of(context).size.width / 8,
                              color: Colors.red.withOpacity(0.2),
                            )
                          : const SizedBox(),
                      // Text(index.toString()),
                      piece == 0
                          ? isSquareValid
                              ? Container(
                                  margin: const EdgeInsets.all(15),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey,
                                  ),
                                )
                              : const SizedBox()
                          : Stack(
                              children: [
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
