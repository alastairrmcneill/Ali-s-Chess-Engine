import 'dart:math';

import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/engines/v12/core/board.dart';
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

const _knightD = [
  [-2, -1], [-2, 1], [-1, -2], [-1, 2], [1, -2], [1, 2], [2, -1], [2, 1], //
];
// First four orthogonal, last four diagonal.
const _dirs = [
  [-1, 0], [0, 1], [1, 0], [0, -1], [-1, 1], [1, 1], [1, -1], [-1, -1], //
];

bool _in(int r, int f) => r >= 0 && r < 8 && f >= 0 && f < 8;

/// Naive reference: walk the mailbox. Piece code: type = p & 7, colour = p >> 3. Index 0 = a8.
int _naiveAttackers(Board b, int sq, int by) {
  final s = b.squares;
  final r = sq >> 3, f = sq & 7;
  int result = 0;

  for (final d in _knightD) {
    final nr = r + d[0], nf = f + d[1];
    if (!_in(nr, nf)) continue;
    final p = s[nr * 8 + nf];
    if (p != 0 && p >> 3 == by && (p & 7) == 3) result |= 1 << (nr * 8 + nf);
  }
  for (final d in _dirs) {
    final nr = r + d[0], nf = f + d[1];
    if (!_in(nr, nf)) continue;
    final p = s[nr * 8 + nf];
    if (p != 0 && p >> 3 == by && (p & 7) == 1) result |= 1 << (nr * 8 + nf);
  }
  // A white pawn attacks towards rank 8 (lower row), so it stands on the row below the target square.
  final pr = by == 0 ? r + 1 : r - 1;
  for (final df in [-1, 1]) {
    if (!_in(pr, f + df)) continue;
    final p = s[pr * 8 + f + df];
    if (p != 0 && p >> 3 == by && (p & 7) == 2) result |= 1 << (pr * 8 + f + df);
  }
  for (int i = 0; i < 8; i++) {
    int nr = r + _dirs[i][0], nf = f + _dirs[i][1];
    while (_in(nr, nf)) {
      final p = s[nr * 8 + nf];
      if (p != 0) {
        final t = p & 7;
        if (p >> 3 == by && (t == 6 || (i < 4 ? t == 5 : t == 4))) result |= 1 << (nr * 8 + nf);
        break;
      }
      nr += _dirs[i][0];
      nf += _dirs[i][1];
    }
  }
  return result;
}

void main() {
  Zobrist.ensureInitialised();

  // The old generator drives the playouts, so this test does not depend on the new generator being finished.
  test('attackersOfSquare equals a naive mailbox walk, every square, both colours, over random playouts', () {
    final rng = Random(11);
    final gen = MoveGenerator();
    int checks = 0;

    for (final fen in _fens) {
      for (int game = 0; game < 15; game++) {
        final b = Board.fromFEN(fen);
        for (int ply = 0; ply < 80; ply++) {
          final occ = b.colourBB[0] | b.colourBB[1];
          for (int by = 0; by < 2; by++) {
            for (int sq = 0; sq < 64; sq++) {
              final actual = b.attackersOfSquare(sq, occ, by);
              final expected = _naiveAttackers(b, sq, by);
              expect(actual, expected,
                  reason: 'fen=$fen game=$game ply=$ply sq=${BoardHelper.squareName(sq)} '
                      'by=${by == 0 ? 'white' : 'black'} actual=0x${actual.toRadixString(16)} '
                      'expected=0x${expected.toRadixString(16)}');
              checks++;
            }
          }
          final moves = List.of(gen.generateLegalMoves(b));
          if (moves.isEmpty) break;
          b.makeMove(moves[rng.nextInt(moves.length)]);
        }
      }
    }
    expect(checks, greaterThan(50000));
  });

  test('pawn attackers: hand-checked', () {
    // White king e1, black pawns on d2 and f2 attack it. Black pawn on e2 does not.
    final b = Board.fromFEN('4k3/8/8/8/8/8/3pPp2/4K3 w - - 0 1');
    final e1 = BoardHelper.squareIndex('e1');
    final occ = b.colourBB[0] | b.colourBB[1];
    final expected = (1 << BoardHelper.squareIndex('d2')) | (1 << BoardHelper.squareIndex('f2'));
    expect(b.attackersOfSquare(e1, occ, 1), expected);
    // Black king e8 with white pawn on e7 is not attacked by it (pawns attack diagonally).
    final c = Board.fromFEN('4k3/4P3/8/8/8/8/8/4K3 b - - 0 1');
    final occC = c.colourBB[0] | c.colourBB[1];
    expect(c.attackersOfSquare(BoardHelper.squareIndex('e8'), occC, 0), 0);
  });
}
