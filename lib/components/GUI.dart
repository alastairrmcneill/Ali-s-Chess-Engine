// ignore_for_file: file_names

import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/components/square.dart';
import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GUI extends StatefulWidget {
  const GUI({super.key});

  @override
  State<GUI> createState() => _GUIState();
}

class _GUIState extends State<GUI> {
  TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    GameProvider gameProvider = Provider.of<GameProvider>(context, listen: false);
    _controller = TextEditingController(text: gameProvider.thinkingTime.toString());
  }

  void onSquareTapped(GameProvider gameProvider, int index) async {
    // Only allow interaction when game is still in playing state
    if (gameProvider.isPlaying) {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Opponent: "),
                DropdownButton<String>(
                  value: gameProvider.engineId,
                  items: [
                    for (final id in gameProvider.engineIds) DropdownMenuItem(value: id, child: Text('ACE $id')),
                  ],
                  // Changing the version starts a new game.
                  onChanged: gameProvider.engineThinking
                      ? null
                      : (id) {
                          if (id != null) gameProvider.setEngine(id);
                        },
                ),
              ],
            ),
            Text("Turn: ${gameProvider.whiteToPlay ? "White" : "Black"}"),
            Expanded(
              flex: 1,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 64,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
                itemBuilder: (context, index) {
                  int rank = BoardHelper.getRankFromIndex(index);
                  int file = BoardHelper.getFileFromIndex(index);
                  bool isWhite = (rank + file) % 2 == 0;
                  bool isSelected = index == gameProvider.selectedIndex;
                  int piece = gameProvider.pieceAt(index);

                  bool isDraggable = false;
                  // If peice is white and whites turn
                  if ((Piece.isColor(piece, Piece.white) && gameProvider.whiteToPlay)) {
                    isDraggable = true;
                  }

                  // Or Piece is black and blacks turn
                  if ((Piece.isColor(piece, Piece.black) && !gameProvider.whiteToPlay)) {
                    isDraggable = true;
                  }

                  // Check if square is valid move option
                  int? selectedIndex = gameProvider.selectedIndex;
                  bool isSquareValid =
                      selectedIndex != null && gameProvider.legalTargetsFrom(selectedIndex).contains(index);

                  // Last move highlight
                  final lastMove = gameProvider.lastMove;

                  return DragTarget<int>(
                    onAccept: (receivedPiece) {
                      // If drag is allowed then play the move
                      gameProvider.move(index);
                    },
                    onWillAccept: (data) {
                      // Decide if allowed to drop on target square
                      return gameProvider.isMoveValid(index);
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Square(
                        index: index,
                        isWhite: isWhite,
                        isSelected: isSelected,
                        isSquareValid: isSquareValid,
                        isDraggable: isDraggable,
                        isLastMove: lastMove != null && (index == lastMove.from || index == lastMove.to),
                        piece: piece,
                        onTap: () => onSquareTapped(gameProvider, index),
                        onDragComplete: () {}, // the provider moves the piece when the drop is accepted
                        onDragStarted: () => gameProvider.selectedIndex = index,
                        onDragableCancelled: (p0, p1) => gameProvider.selectedIndex = null,
                      );
                    },
                  );
                },
              ),
            ),
            Text(gameProvider.engineThinking ? "Engine is thinking" : "Engine is idle"),
            Text(gameProvider.gameEnd?.toString() ?? "Playing"),
            if (gameProvider.engineProblem != null)
              Text(gameProvider.engineProblem!, style: const TextStyle(color: Colors.red)),
            const Text("Thinking time (ms)"),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  int? time = int.tryParse(value);

                  if (time == null) return;
                  gameProvider.thinkingTime = time;
                },
              ),
            ),
            ElevatedButton(
              onPressed: () => setState(() => gameProvider.reset()),
              child: const Text("Reset"),
            ),
            ElevatedButton(
              onPressed: () async {
                await gameProvider.startAIGame();
              },
              child: const Text("Start AI Game"),
            ),
          ],
        ),
      ),
    );
  }
}
