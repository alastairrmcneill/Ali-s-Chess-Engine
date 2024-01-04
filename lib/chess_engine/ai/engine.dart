import 'dart:math';

import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';

class Engine {
  static Move getBestMove(Board board) {
    MoveGenerator moveGenerator = MoveGenerator();
    List<Move> legalMoves = moveGenerator.generateLegalMoves(board);
    Random random = Random();
    return legalMoves[random.nextInt(legalMoves.length)];
    // return legalMoves[0];
  }
}
