import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';

class Engine {
  static Move getBestMove(Board board) {
    MoveGenerator moveGenerator = MoveGenerator();
    List<Move> legalMoves = moveGenerator.generateLegalMoves2(board);
    return legalMoves[0];
  }
}
