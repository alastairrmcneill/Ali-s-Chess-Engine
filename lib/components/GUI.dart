// ignore_for_file: file_names

import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/piece.dart';
import 'package:ace/components/square.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GUI extends StatefulWidget {
  const GUI({super.key});

  @override
  State<GUI> createState() => _GUIState();
}

class _GUIState extends State<GUI> {
  @override
  void initState() {
    super.initState();
    GameProvider gameProvider = Provider.of<GameProvider>(context, listen: false);
    gameProvider.reset();
  }

  void onSquareTapped(GameProvider gameProvider, int index) async {
    if (gameProvider.gameResult == Result.playing) {
      gameProvider.select(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    GameProvider gameProvider = Provider.of<GameProvider>(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Text("Turn: ${gameProvider.whiteToPlay ? "White" : "Black"}"),
            Text("Current Eval: ${gameProvider.currentEval}"),
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
                  bool isSelected = index == gameProvider.selectedIndex;
                  bool isSquareValid = false;

                  bool isDraggable = false;
                  // If peice is white and whites turn
                  if ((Piece.color(gameProvider.board.position[index]) == Piece.white && gameProvider.whiteToPlay)) {
                    isDraggable = true;
                  }

                  // Or Piece is black and blacks turn

                  if ((Piece.color(gameProvider.board.position[index]) == Piece.black && !gameProvider.whiteToPlay)) {
                    isDraggable = true;
                  }

                  // Check if square is valid move option
                  if (gameProvider.selectedIndex != null) {
                    List<Move> selectPieceMoves = gameProvider.legalMoves
                        .where((move) => move.startingSquare == gameProvider.selectedIndex)
                        .toList();

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
                      gameProvider.move(index);
                    },
                    onWillAccept: (data) {
                      // Decide if I can land here
                      return gameProvider.isMoveValid(index);
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Square(
                        index: index,
                        isSquareAttacked: false, // gameProvider.moveGenerator.opponentAttackMap.contains(index),
                        isWhite: isWhite,
                        isSelected: isSelected,
                        isSquareValid: isSquareValid,
                        isDraggable: isDraggable,
                        piece: gameProvider.board.position[index],
                        onTap: () => onSquareTapped(gameProvider, index),
                        onDragComplete: () => gameProvider.board.position[index] = 0,
                        onDragStarted: () {
                          gameProvider.selectedIndex = index;
                        },
                        onDragableCancelled: (p0, p1) {
                          gameProvider.selectedIndex = null;
                        },
                      );
                    },
                  );
                },
              ),
            ),
            Text(gameProvider.engineThinking ? "Engine is thinking" : "Engine is idle"),
            Text(
                "Evaluated ${gameProvider.numPositionsEvaluated} positions in ${gameProvider.searchDuration.inMilliseconds}ms"),
            Text(gameProvider.gameResult.toString()),
            gameProvider.gameResult == Result.playing
                ? const SizedBox()
                : ElevatedButton(
                    onPressed: () => setState(() => gameProvider.reset()),
                    child: Text("Reset"),
                  ),
            // ElevatedButton(
            //   onPressed: () => Tests.testMoveGeneration(gameProvider.board),
            //   child: Text("Test move gen"),
            // ),
            ElevatedButton(
              onPressed: () => gameProvider.startAIGame(),
              child: Text("Start AI Game"),
            ),
          ],
        ),
      ),
    );
  }
}
