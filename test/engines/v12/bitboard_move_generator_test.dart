import 'dart:math';

import 'package:ace/engines/v12/core/move_generator.dart';
import 'package:ace/engines/v12/core/board.dart';
import 'package:ace/engines/v12/core/move.dart';
import 'package:ace/engines/v12/core/move_generator.dart';
import 'package:ace/engines/v12/core/zobrist.dart';
import 'package:flutter_test/flutter_test.dart';

const _fens = [
  'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
  'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
  'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
  'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
];

// [fen index, depth, expected nodes]
const _perft = [
  [0, 4, 197281],
  [1, 3, 97862],
  [2, 4, 43238],
  [3, 3, 9467],
  [4, 3, 62379],
  [5, 3, 89890],
];

int _perftCount(Board b, BitboardMoveGenerator gen, int depth) {
  final moves = List<Move>.of(gen.generate(b));
  if (depth == 1) return moves.length;
  int n = 0;
  for (final m in moves) {
    b.makeMove(m);
    n += _perftCount(b, gen, depth - 1);
    b.unMakeMove(m);
  }
  return n;
}

bool _isCapture(Board b, Move m) => b.squares[m.to] != 0 || m.enPassantCapture;

Set<int> _set(List<Move> m) => m.map((e) => e.value).toSet();

void main() {
  Zobrist.ensureInitialised();

  group('BitboardMoveGenerator perft', () {
    for (final p in _perft) {
      test('fen ${p[0]} depth ${p[1]}', () {
        final b = Board.fromFEN(_fens[p[0]]);
        expect(_perftCount(b, BitboardMoveGenerator(), p[1]), p[2]);
      });
    }
  });

  group('BitboardMoveGenerator vs mailbox generator', () {
    test('random playouts: same legal moves, captures-only moves and check status', () {
      final rng = Random(7);
      final oldGen = MoveGenerator();
      final newGen = BitboardMoveGenerator();
      int steps = 0;
      for (final fen in _fens) {
        for (int game = 0; game < 25; game++) {
          final b = Board.fromFEN(fen);
          for (int ply = 0; ply < 120; ply++) {
            for (final capturesOnly in [false, true]) {
              var expectedMoves = List.of(oldGen.generateLegalMoves(b));
              // Old generator's quiet-less mode still returns quiet evasions when in check; new capturesOnly is strict.
              if (capturesOnly) expectedMoves = expectedMoves.where((m) => _isCapture(b, m)).toList();
              final expected = _set(expectedMoves);
              final actualMoves = newGen.generate(b, capturesOnly: capturesOnly);
              final actual = _set(actualMoves);
              final reason = 'fen=$fen game=$game ply=$ply capturesOnly=$capturesOnly';
              expect(actualMoves.length, actual.length, reason: 'duplicate moves, $reason');
              expect(actual, expected, reason: reason);
            }
            expect(b.isInCheck(), oldGen.isInCheck(b), reason: 'fen=$fen game=$game ply=$ply');
            final moves = newGen.generate(b);
            if (moves.isEmpty) break;
            b.makeMove(moves[rng.nextInt(moves.length)]);
            steps++;
          }
        }
      }
      expect(steps, greaterThan(1000));
    });
  });
}
