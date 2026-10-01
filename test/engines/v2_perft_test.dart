// Perft tests for v2's own move generator (lib/engines/v2/core), using the correct counts.
//
// v2 starts as an exact copy of v1, so "position 3" (depth 5) and "position 5" (depth 4) fail until the sliding
// piece bug is fixed (docs/engine_v1_known_issues.md, issue #1). Everything else should already pass.
//
//   flutter test test/engines/v2_perft_test.dart
//   flutter test test/engines/v2_perft_test.dart --plain-name "position 3"
//
// Divide (node count after each first move) for any FEN, to track down a wrong count:
//   PERFT_FEN="8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1" PERFT_DEPTH=3 \
//     flutter test test/engines/v2_perft_test.dart --plain-name divide
import 'dart:io';

import 'package:ace/engines/v2/core/board.dart';
import 'package:ace/engines/v2/core/move.dart';
import 'package:ace/engines/v2/core/move_generator.dart';
import 'package:ace/engines/v2/core/zobrist.dart';
import 'package:flutter_test/flutter_test.dart';

import '../perft_positions.dart';

const String _files = "abcdefgh";

String _moveName(Move move) {
  String square(int index) => "${_files[index % 8]}${8 - index ~/ 8}";
  return "${square(move.startingSquare)}${square(move.targetSquare)}${move.promotion == 0 ? "" : " qnrb"[move.promotion]}";
}

int perft(MoveGenerator moveGenerator, Board board, int depth) {
  List<Move> moves = List.of(moveGenerator.generateLegalMoves(board));
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
  Zobrist(); // v2's hash keys must exist before any v2 board is made

  group("v2 perft", () {
    for (PerftCase perftCase in perftCases) {
      for (int depth = 1; depth <= perftCase.expected.length; depth++) {
        test("${perftCase.name} depth $depth", () {
          expect(perft(MoveGenerator(), Board.fromFen(perftCase.fen), depth), perftCase.expected[depth - 1]);
        }, timeout: const Timeout(Duration(minutes: 10)));
      }
    }
  });

  test("divide", () {
    String fen = Platform.environment["PERFT_FEN"] ?? perftCases.first.fen;
    int depth = int.parse(Platform.environment["PERFT_DEPTH"] ?? "2");
    Board board = Board.fromFen(fen);
    MoveGenerator moveGenerator = MoveGenerator();
    int total = 0;
    List<String> lines = [];
    for (Move move in List.of(moveGenerator.generateLegalMoves(board))) {
      board.makeMove(move);
      int nodes = depth == 1 ? 1 : perft(moveGenerator, board, depth - 1);
      board.unMakeMove(move);
      total += nodes;
      lines.add("${_moveName(move)}: $nodes");
    }
    lines.sort();
    // ignore: avoid_print
    print("${lines.join("\n")}\n\nTotal: $total  (depth $depth, $fen)");
  });
}
