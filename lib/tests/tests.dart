import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';

class Tests {
  static testMoveGeneration(Board board) {
    MoveGenerator moveGenerator = MoveGenerator();
    int testDepth = 5;
    List<int> expectedResults = [
      0,
      20,
      400,
      8902,
      197281,
      4865609,
      119060324,
    ];
    // List<int> expectedResults = [
    //   0,
    //   46,
    //   2079,
    //   89890,
    //   3894594,
    //   164075551,
    //   706045033,
    // ];

    for (int depth = 1; depth <= testDepth; depth++) {
      int numMoves = 0;

      DateTime start = DateTime.now();
      numMoves += _search(moveGenerator, board, depth);
      DateTime end = DateTime.now();

      print(
          "Found $numMoves moves after $depth ply in ${end.difference(start).inMilliseconds}ms. - Test ${numMoves == expectedResults[depth] ? "Passed" : "Failed"}");
    }
  }

  static int _search(MoveGenerator moveGenerator, Board board, int depth) {
    // List<Move> moves = moveGenerator.generateMoves(board);

    List<Move> moves = moveGenerator.generateLegalMoves(board);

    if (depth == 1) {
      return moves.length;
    } else {
      int numMovesForThisPosition = 0;
      for (Move move in moves) {
        board.makeMove(move);
        int numMovesAfterThisMove = _search(moveGenerator, board, depth - 1);
        numMovesForThisPosition += numMovesAfterThisMove;
        board.unMakeMove(move);
        // if (depth == 4) {
        //   print("${move.toChessNotation()} - $numMovesAfterThisMove");
        // }
      }

      return numMovesForThisPosition;
    }
  }
}
