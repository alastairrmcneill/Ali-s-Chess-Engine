import 'dart:math';

import 'package:ace/chess_engine/helpers/board_helper.dart';

// Run once at the start of the program to get common information in the move generation sequence

class PrecomputeData {
  // First 4 are orthogonal, last 4 are diagonals (N, E, S, W, NE, SE, SW, NW)
  final List<int> directionOffsets = [-8, 1, 8, -1, -7, 9, 7, -9];
  late List<List<int>> numSquaresToEdge;
  late List<List<int>> knightMoves;
  late List<List<int>> kingMoves;
  late List<List<int>> whitePawnCaptures;
  late List<List<int>> blackPawnCaptures;
  late List<int> cmd = [
    // Central Manhattan Distance for king end games
    6, 5, 4, 3, 3, 4, 5, 6,
    5, 4, 3, 2, 2, 3, 4, 5,
    4, 3, 2, 1, 1, 2, 3, 4,
    3, 2, 1, 0, 0, 1, 2, 3,
    3, 2, 1, 0, 0, 1, 2, 3,
    4, 3, 2, 1, 1, 2, 3, 4,
    5, 4, 3, 2, 2, 3, 4, 5,
    6, 5, 4, 3, 3, 4, 5, 6,
  ];

  PrecomputeData() {
    numSquaresToEdge = List.generate(64, (index) => []);
    knightMoves = List.generate(64, (index) => []);
    kingMoves = List.generate(64, (index) => []);
    whitePawnCaptures = List.generate(64, (index) => []);
    blackPawnCaptures = List.generate(64, (index) => []);

    for (int index = 0; index < 64; index++) {
      int rank = BoardHelper.getRankFromIndex(index);
      int file = BoardHelper.getFileFromIndex(index);

      // Num squares to edge
      int north = rank;
      int south = 7 - rank;
      int east = 7 - file;
      int west = file;
      numSquaresToEdge[index] = List.generate(8, (index) => 0);
      numSquaresToEdge[index][0] = north;
      numSquaresToEdge[index][1] = east;
      numSquaresToEdge[index][2] = south;
      numSquaresToEdge[index][3] = west;
      numSquaresToEdge[index][4] = min(north, east);
      numSquaresToEdge[index][5] = min(south, east);
      numSquaresToEdge[index][6] = min(south, west);
      numSquaresToEdge[index][7] = min(north, west);

      // King moves
      kingMoves[index] = [];
      for (int offset in directionOffsets) {
        int targetIndex = index + offset;
        if (targetIndex >= 0 && targetIndex < 64) {
          int targetIndexCol = targetIndex % 8;
          int startingIndexCol = index % 8;
          if ((targetIndexCol - startingIndexCol).abs() <= 1) {
            kingMoves[index].add(targetIndex);
          }
        }
      }

      // Knight moves
      List<int> knightOffsets = [-10, -17, -15, -6, 10, 17, 15, 6];
      knightMoves[index] = [];
      for (int offset in knightOffsets) {
        int targetIndex = index + offset;
        if (targetIndex >= 0 && targetIndex < 64) {
          int targetIndexCol = targetIndex % 8;
          int startingIndexCol = index % 8;
          if ((targetIndexCol - startingIndexCol).abs() <= 2) {
            knightMoves[index].add(targetIndex);
          }
        }
      }

      // White pawn captures
      whitePawnCaptures[index] = [];

      // Decide what the attack squares should be
      int targetIndexCaptureLeft = index - 8 - 1;
      int targetIndexCaptureRight = index - 8 + 1;

      // Determine if left capture is in bounds of board and doesn't wrap to other side
      if (targetIndexCaptureLeft >= 0 && targetIndexCaptureLeft < 64) {
        int targetIndexCaptureLeftFile = BoardHelper.getFileFromIndex(targetIndexCaptureLeft);
        if ((targetIndexCaptureLeftFile - file).abs() == 1) {
          whitePawnCaptures[index].add(targetIndexCaptureLeft);
        }
      }

      // Determine if right capture is in bounds of board and doesn't wrap to the other side
      if (targetIndexCaptureRight >= 0 && targetIndexCaptureRight < 64) {
        int targetIndexCaptureRightCol = BoardHelper.getFileFromIndex(targetIndexCaptureRight);
        if ((targetIndexCaptureRightCol - file).abs() == 1) {
          whitePawnCaptures[index].add(targetIndexCaptureRight);
        }
      }

      // Black pawn captures
      blackPawnCaptures[index] = [];

      // Define possible attack squares
      targetIndexCaptureLeft = index + 8 - 1;
      targetIndexCaptureRight = index + 8 + 1;

      // Determine if left capture is in bounds of board and doesn't wrap to the other side
      if (targetIndexCaptureLeft >= 0 && targetIndexCaptureLeft < 64) {
        int targetIndexCaptureLeftFile = BoardHelper.getFileFromIndex(targetIndexCaptureLeft);
        if ((targetIndexCaptureLeftFile - file).abs() == 1) {
          blackPawnCaptures[index].add(targetIndexCaptureLeft);
        }
      }

      // Determine if right capture is in bounds of board and doesn't wrap to the other side
      if (targetIndexCaptureRight >= 0 && targetIndexCaptureRight < 64) {
        int targetIndexCaptureRightFile = BoardHelper.getFileFromIndex(targetIndexCaptureRight);
        if ((targetIndexCaptureRightFile - file).abs() == 1) {
          blackPawnCaptures[index].add(targetIndexCaptureRight);
        }
      }
    }
  }
}
