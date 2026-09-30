import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/move_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../perft_positions.dart';

int perft(MoveGenerator moveGenerator, Board board, int depth) {
  List<Move> moves = moveGenerator.generateLegalMoves(board);
  if (depth == 1) return moves.length;

  int nodes = 0;
  for (Move move in moves) {
    board.makeMove(move);
    nodes += perft(moveGenerator, board, depth - 1);
    board.unMakeMove(move);
  }
  return nodes;
}

void main() {
  group("chess_core perft", () {
    for (PerftCase perftCase in perftCases) {
      test(perftCase.name, () {
        Board board = Board.fromFen(perftCase.fen);
        String fenBefore = board.toFen();
        for (int depth = 1; depth <= perftCase.expected.length; depth++) {
          expect(perft(MoveGenerator(), board, depth), perftCase.expected[depth - 1], reason: "depth $depth");
        }
        expect(board.toFen(), fenBefore, reason: "make/unmake should restore the position");
      });
    }
  });
}
