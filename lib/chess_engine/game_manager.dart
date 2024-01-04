import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';
import 'package:ace/chess_engine/piece.dart';

class Game {
  late MoveGenerator moveGenerator;
  late Board board;
  late List<Move> legalMoves;
  late int? selectedIndex;
  late Result gameResult;

  Game() {
    board = Board();
    moveGenerator = MoveGenerator();
    selectedIndex = null;
    gameResult = Result.playing;
    legalMoves = [];
    legalMoves = moveGenerator.generateLegalMoves(board);
  }

  reset() {
    board = Board();
    moveGenerator = MoveGenerator();
    selectedIndex = null;
    gameResult = Result.playing;
    legalMoves = [];
    legalMoves = moveGenerator.generateLegalMoves(board);
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
    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);

    for (var move in legalMoves) {
      if (move.startingSquare == selectedIndex && move.targetSquare == targetIndex) {
        return true;
      }
    }
    return false;
  }

  move(int targetIndex) {
    for (var move in legalMoves) {
      if (move.startingSquare == selectedIndex && move.targetSquare == targetIndex) {
        board.makeMove(move);
        // board.unMakeMove(move);
        selectedIndex = null;
        getGameResult();

        return true;
      }
    }
    return false;
  }

  getGameResult() {
    // Check checkmate and stalemate
    // print("Get Game Result");
    legalMoves = moveGenerator.generateLegalMoves(board);
    if (legalMoves.isEmpty) {
      if (moveGenerator.opponentAttackMap.contains(moveGenerator.opponentKingIndex)) {
        gameResult = board.whiteToPlay ? Result.whiteIsMated : Result.blackIsMated;
        return;
      }
      gameResult = Result.stalemate;
      return;
    }

    // Check 50 moves
    if (board.fiftyMoveRule >= 100) {
      gameResult = Result.fiftyMoveRule;
      return;
    }

    // Check 3 repetition
    Map<String, int> occurrenceMap = {};

    for (var list in board.positionRepetitionHistory) {
      // Convert the list to a string to use as a key in the map
      String key = list.toString();

      // Update the occurrence count for this list
      if (!occurrenceMap.containsKey(key)) {
        occurrenceMap[key] = 1;
      } else {
        occurrenceMap[key] = (occurrenceMap[key] as int) + 1;
      }

      // Check if this list has occurred 3 times
      if (occurrenceMap[key] == 3) {
        gameResult = Result.repeition;
        return;
      }
    }

    // Check insufficient material
    int numQueens = 0;
    int numRooks = 0;
    int numBishops = 0;
    List<int> whiteBishops = [];
    List<int> blackBishops = [];
    int numKnights = 0;
    int numPawns = 0;

    for (int i = 0; i < board.position.length; i++) {
      int piece = board.position[i];

      int pieceType = Piece.pieceType(piece);
      switch (pieceType) {
        case Piece.queen:
          numQueens++;
          break;
        case Piece.rook:
          numRooks++;
          break;
        case Piece.bishop:
          numBishops++;
          Piece.isColor(piece, Piece.white) ? whiteBishops.add(i) : blackBishops.add(i);
          break;
        case Piece.knight:
          numKnights++;
          break;
        case Piece.pawn:
          numPawns++;
          break;
        default:
          break;
      }
    }

    if (numPawns + numRooks + numQueens + numKnights + numBishops == 0) {
      gameResult = Result.insufficientMaterial;
      return;
    } else if (numPawns + numRooks + numQueens == 0) {
      if (numKnights == 1 || numBishops == 1) {
        gameResult = Result.insufficientMaterial;
        return;
      }

      if (numKnights == 0 && whiteBishops.length == 1 && blackBishops.length == 1) {
        // Check if the bishops are on the same squares
        int whiteBishopRank = whiteBishops[0] % 8;
        int whiteBishopFile = whiteBishops[0] ~/ 8;
        int blackBishopRank = blackBishops[0] % 8;
        int blackBishopFile = blackBishops[0] ~/ 8;
        int whiteSquareColor = (whiteBishopFile + whiteBishopRank) % 2;
        int blackSquareColor = (blackBishopFile + blackBishopRank) % 2;

        if (whiteSquareColor == blackSquareColor) {
          gameResult = Result.insufficientMaterial;
          return;
        }
      }
    }

    // If all pass then we are still playing

    gameResult = Result.playing;
  }
}

enum Result {
  playing,
  whiteIsMated,
  blackIsMated,
  stalemate,
  repeition,
  fiftyMoveRule,
  insufficientMaterial,
}
