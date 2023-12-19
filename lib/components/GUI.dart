import 'package:ace/chess_engine/game_manager.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';
import 'package:ace/chess_engine/piece.dart';
import 'package:ace/components/square.dart';
import 'package:flutter/material.dart';

class GUI extends StatefulWidget {
  const GUI({super.key});

  @override
  State<GUI> createState() => _GUIState();
}

class _GUIState extends State<GUI> {
  late Game game;

  @override
  void initState() {
    super.initState();
    game = Game();
  }

  void onSquareTapped(int index) {
    setState(() {
      game.select(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Move> possibleMoves = MoveGenerator().generateMoves(game.board);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Text("Turn: ${game.isWhiteToPlay() ? "White" : "Black"}"),
            Expanded(
              flex: 1,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 64,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
                itemBuilder: (context, index) {
                  int row = index ~/ 8;
                  int col = index % 8;
                  bool isWhite = (row + col) % 2 == 0;
                  bool isSelected = index == game.selectedIndex;
                  bool isSquareValid = false;

                  bool isDraggable = false;
                  // If peice is white and whites turn
                  if ((Piece.color(game.board.position[index]) == Piece.white && game.isWhiteToPlay())) {
                    isDraggable = true;
                  }

                  // Or Piece is black and blacks turn

                  if ((Piece.color(game.board.position[index]) == Piece.black && !game.isWhiteToPlay())) {
                    isDraggable = true;
                  }

                  // Check if square is valid move option
                  if (game.selectedIndex != null) {
                    List<Move> selectPieceMoves =
                        possibleMoves.where((move) => move.startingSquare == game.selectedIndex).toList();

                    for (var i = 0; i < selectPieceMoves.length; i++) {
                      Move move = selectPieceMoves[i];

                      if (move.targetSquare == index) {
                        isSquareValid = true;
                        break;
                      }
                    }
                  }

                  return DragTarget<int>(
                    onAccept: (receivedPiece) {
                      setState(() {
                        game.move(index);
                      });
                    },
                    onWillAccept: (data) {
                      // Decide if I can land here
                      return game.isMoveValid(index);
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Square(
                        index: index,
                        isWhite: isWhite,
                        isSelected: isSelected,
                        isSquareValid: isSquareValid,
                        isDraggable: isDraggable,
                        piece: game.board.position[index],
                        onTap: () => onSquareTapped(index),
                        onDragComplete: () => game.board.position[index] = 0,
                        onDragStarted: () {
                          setState(() {
                            game.selectedIndex = index;
                          });
                        },
                        onDragableCancelled: (p0, p1) {
                          setState(() {
                            game.selectedIndex = null;
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
