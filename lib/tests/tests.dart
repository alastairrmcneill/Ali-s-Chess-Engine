import 'package:ace/chess_engine/ai/transposition_table.dart';
import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/fen_utility.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';

class Tests {
  static int transpositionsFound = 0;
  static testMoveGeneration(Board board) {
    MoveGenerator moveGenerator = MoveGenerator();
    int testDepth = 6;
    // List<int> expectedResults = [
    //   0,
    //   20,
    //   400,
    //   8902,
    //   197281,
    //   4865609,
    //   119060324,
    // ];
    List<int> expectedResults = [
      0,
      48,
      2039,
      97862,
      4085603,
      193690690,
      11030083,
    ];

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

        // if (depth == 2) {
        //   print("${move.toChessNotation()} - $numMovesAfterThisMove");
        // }
      }

      return numMovesForThisPosition;
    }
  }

  // static testZobristHashing(Board board) {
  //   MoveGenerator moveGenerator = MoveGenerator();
  //   TranspositionTable transpositionTable = TranspositionTable(1000000000);
  //   List<int> expectedResults = [
  //     0,
  //     0,
  //     0,
  //     1300,
  //     4085603,
  //     193690690,
  //     11030083,
  //   ];

  //   int testDepth = 4;
  //   for (int depth = 1; depth <= testDepth; depth++) {
  //     transpositionsFound = 0;
  //     DateTime start = DateTime.now();
  //     _zobristSearch(moveGenerator, transpositionTable, board, depth);
  //     DateTime end = DateTime.now();

  //     print(
  //         "Found $transpositionsFound transpositions after $depth ply in ${end.difference(start).inMilliseconds}ms. - Test ${transpositionsFound == expectedResults[depth] ? "Passed" : "Failed"}");
  //   }
  // }

  // static _zobristSearch(MoveGenerator moveGenerator, TranspositionTable transpositionTable, Board board, int depth) {
  //   List<Move> moves = moveGenerator.generateLegalMoves(board);

  //   int zobrist = board.zobristKey;

  //   if (depth == 1) {
  //     var entry = transpositionTable.retrieve(zobrist);
  //     if (entry != null) {
  //       transpositionsFound += 1;
  //       print("Current state - ${FENUtility.fenFromBoard(board)}");
  //       print("Stored History");
  //       for (Move move in entry.history) print(move);
  //       print("Current History");
  //       for (Move move in board.moveHistory) print(move);
  //     } else {
  //       print("Saving History");
  //       for (Move move in board.moveHistory) print(move);
  //       transpositionTable.addEntry(
  //         TranspositionTableEntry(
  //           zobristHash: board.zobristKey,
  //           history: board.moveHistory,
  //         ),
  //       );
  //     }
  //   } else {
  //     for (Move move in moves) {
  //       board.makeMove(move);
  //       _zobristSearch(moveGenerator, transpositionTable, board, depth - 1);
  //       board.unMakeMove(move);
  //     }

  //     return;
  //   }
  // }
}
