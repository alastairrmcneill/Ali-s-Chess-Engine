import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';
import 'package:ace/chess_engine/piece.dart';

class Game {
  late MoveGenerator moveGenerator;
  late Board board;
  late int? selectedIndex;

  Game() {
    board = Board();
    moveGenerator = MoveGenerator();

    selectedIndex = null;
  }

  bool isWhiteToPlay() {
    return board.whiteToPlay;
  }

  select(int index) {
    if (selectedIndex != null) {
      // If something has been selected already then try to see if we can move there
      bool result = move(index);
      if (!result) {
        selectedIndex = null;
        select(index);
      }
    } else {
      // If not then set this peiece to be selected, unless its an empty square and set selected to be null
      if (board.position[index] == 0) {
        selectedIndex = null;
      } else {
        if ((isWhiteToPlay() && Piece.isColor(board.position[index], Piece.white)) ||
            (!isWhiteToPlay() && Piece.isColor(board.position[index], Piece.black))) {
          selectedIndex = index;
        }
      }
    }
  }

  bool isMoveValid(int targetIndex) {
    List<Move> legalMoves = moveGenerator.generateMoves(board);

    for (var move in legalMoves) {
      if (move.startingSquare == selectedIndex && move.targetSquare == targetIndex) {
        return true;
      }
    }
    return false;
  }

  move(int targetIndex) {
    int selectedPiece = board.position[selectedIndex!];
    // int targetPiece = board.position[targetIndex];

    List<Move> legalMoves = moveGenerator.generateMoves(board);

    for (var move in legalMoves) {
      if (move.startingSquare == selectedIndex && move.targetSquare == targetIndex) {
        board.position[targetIndex] = selectedPiece;
        board.position[selectedIndex!] = 0;
        selectedIndex = null;
        board.whiteToPlay = !board.whiteToPlay;
        return true;
      }
    }
    return false;
  }
}
