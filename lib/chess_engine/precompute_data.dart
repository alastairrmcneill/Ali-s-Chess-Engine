import 'dart:math';

class PrecomputeData {
  // First 4 are orthogonal, last 4 are diagonals (N, S, W, E, NW, SE, NE, SW)
  late List<int> directionOffsets = [8, -8, -1, 1, 7, -7, 9, -9];
  late List<List<int>> numSquaresToEdge;
  late List<List<int>> knightMoves;
  late List<List<int>> kingMoves;
  late List<List<int>> whitePawnCaptures;
  late List<List<int>> blackPawnCaptures;

  PrecomputeData() {
    numSquaresToEdge = List.generate(64, (index) => []);
    knightMoves = List.generate(64, (index) => []);
    kingMoves = List.generate(64, (index) => []);
    whitePawnCaptures = List.generate(64, (index) => []);
    blackPawnCaptures = List.generate(64, (index) => []);

    for (int index = 0; index < 64; index++) {
      int rank = index ~/ 8;
      int file = index % 8;

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
      List<int> kingOffsets = [-8, 8, -1, 1, -7, 7, -9, 9];
      kingMoves[index] = [];
      for (int offset in kingOffsets) {
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

      int targetIndexCaptureLeft = index - 8 - 1;
      int targetIndexCaptureRight = index - 8 + 1;

      if (targetIndexCaptureLeft >= 0 && targetIndexCaptureLeft < 64) {
        int targetIndexCaptureLeftCol = targetIndexCaptureLeft % 8;
        if ((targetIndexCaptureLeftCol - file).abs() == 1) {
          whitePawnCaptures[index].add(targetIndexCaptureLeft);
        }
      }
      if (targetIndexCaptureRight >= 0 && targetIndexCaptureRight < 64) {
        int targetIndexCaptureLeftCol = targetIndexCaptureRight % 8;
        if ((targetIndexCaptureLeftCol - file).abs() == 1) {
          whitePawnCaptures[index].add(targetIndexCaptureRight);
        }
      }

      // White pawn captures
      blackPawnCaptures[index] = [];

      targetIndexCaptureLeft = index + 8 - 1;
      targetIndexCaptureRight = index + 8 + 1;

      if (targetIndexCaptureLeft >= 0 && targetIndexCaptureLeft < 64) {
        int targetIndexCaptureLeftCol = targetIndexCaptureLeft % 8;
        if ((targetIndexCaptureLeftCol - file).abs() == 1) {
          blackPawnCaptures[index].add(targetIndexCaptureLeft);
        }
      }
      if (targetIndexCaptureRight >= 0 && targetIndexCaptureRight < 64) {
        int targetIndexCaptureLeftCol = targetIndexCaptureRight % 8;
        if ((targetIndexCaptureLeftCol - file).abs() == 1) {
          blackPawnCaptures[index].add(targetIndexCaptureRight);
        }
      }
    }
  }
}
