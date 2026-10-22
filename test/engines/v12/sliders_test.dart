import 'dart:math';

import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/engines/v12/core/attack_tables.dart';
import 'package:ace/engines/v12/core/sliders.dart';
import 'package:flutter_test/flutter_test.dart';

// [rank delta, file delta]. Rank row 0 is rank 8, so -1 is towards rank 8 (north).
const _orthogonal = [
  [-1, 0],
  [1, 0],
  [0, 1],
  [0, -1],
];
const _diagonal = [
  [-1, 1],
  [1, 1],
  [1, -1],
  [-1, -1],
];

/// Reference implementation: walk each direction square by square until the first occupied square (inclusive).
int _naive(int sq, int occ, List<List<int>> dirs) {
  int result = 0;
  for (final d in dirs) {
    int rank = (sq >> 3) + d[0];
    int file = (sq & 7) + d[1];
    while (rank >= 0 && rank < 8 && file >= 0 && file < 8) {
      final bit = 1 << (rank * 8 + file);
      result |= bit;
      if (occ & bit != 0) break;
      rank += d[0];
      file += d[1];
    }
  }
  return result;
}

int _bitsOf(List<String> squares) => squares.fold(0, (acc, s) => acc | (1 << BoardHelper.squareIndex(s)));

void main() {
  final sliders = Sliders(AttackTables());
  final rng = Random(21);
  int random64() => (rng.nextInt(1 << 32) << 32) | rng.nextInt(1 << 32);

  int rook(String sq, List<String> blockers) =>
      sliders.rookAttacks(BoardHelper.squareIndex(sq), _bitsOf(blockers));
  int bishop(String sq, List<String> blockers) =>
      sliders.bishopAttacks(BoardHelper.squareIndex(sq), _bitsOf(blockers));

  group('Sliders, hand-checked cases', () {
    test('rook on an empty board sees its whole rank and file', () {
      final expected = _bitsOf([
        'a4', 'b4', 'c4', 'e4', 'f4', 'g4', 'h4', //
        'd1', 'd2', 'd3', 'd5', 'd6', 'd7', 'd8',
      ]);
      expect(rook('d4', []), expected);
    });

    test('rook stops at the first blocker in every direction and includes it', () {
      // Blockers on all four sides, each with another piece behind it that must not be reached.
      final result = rook('d4', ['d6', 'd7', 'b4', 'a4', 'f4', 'h4', 'd2', 'd1']);
      final expected = _bitsOf(['d5', 'd6', 'c4', 'b4', 'e4', 'f4', 'd3', 'd2']);
      expect(result, expected);
    });

    test('rook east and west cut off at the nearest blocker (regression for swapped E/W)', () {
      expect(rook('d4', ['f4', 'h4']), _bitsOf(['e4', 'f4', 'a4', 'b4', 'c4', 'd1', 'd2', 'd3', 'd5', 'd6', 'd7', 'd8']));
      expect(rook('d4', ['b4', 'a4']), _bitsOf(['c4', 'b4', 'e4', 'f4', 'g4', 'h4', 'd1', 'd2', 'd3', 'd5', 'd6', 'd7', 'd8']));
    });

    test('bishop on an empty board', () {
      final expected = _bitsOf([
        'a1', 'b2', 'c3', 'e5', 'f6', 'g7', 'h8', //
        'a7', 'b6', 'c5', 'e3', 'f2', 'g1',
      ]);
      expect(bishop('d4', []), expected);
    });

    test('bishop stops at the first blocker in every direction and includes it', () {
      final result = bishop('d4', ['f6', 'g7', 'b6', 'a7', 'f2', 'g1', 'c3', 'b2']);
      final expected = _bitsOf(['e5', 'f6', 'c5', 'b6', 'e3', 'f2', 'c3']);
      expect(result, expected);
    });

    test('corner and edge squares', () {
      expect(rook('a8', []), _bitsOf(['b8', 'c8', 'd8', 'e8', 'f8', 'g8', 'h8', 'a7', 'a6', 'a5', 'a4', 'a3', 'a2', 'a1']));
      expect(bishop('h1', []), _bitsOf(['g2', 'f3', 'e4', 'd5', 'c6', 'b7', 'a8']));
      expect(bishop('a8', ['c6']), _bitsOf(['b7', 'c6']));
    });

    test('adjacent blockers', () {
      expect(rook('e4', ['e5', 'e3', 'd4', 'f4']), _bitsOf(['e5', 'e3', 'd4', 'f4']));
      expect(bishop('e4', ['d5', 'f5', 'd3', 'f3']), _bitsOf(['d5', 'f5', 'd3', 'f3']));
    });

    test('the slider square itself in the occupancy is ignored', () {
      final sq = BoardHelper.squareIndex('d4');
      expect(sliders.rookAttacks(sq, 1 << sq), sliders.rookAttacks(sq, 0));
      expect(sliders.bishopAttacks(sq, 1 << sq), sliders.bishopAttacks(sq, 0));
    });

    test('queen is rook | bishop', () {
      for (int sq = 0; sq < 64; sq++) {
        final occ = random64();
        expect(sliders.queenAttacks(sq, occ), sliders.rookAttacks(sq, occ) | sliders.bishopAttacks(sq, occ));
      }
    });
  });

  group('Sliders vs naive walk', () {
    // Mix empty, sparse and dense occupancies, including the extremes with bit 63 set.
    int occupancy(int i) {
      switch (i % 4) {
        case 0:
          return random64();
        case 1:
          return random64() & random64();
        case 2:
          return random64() & random64() & random64();
        default:
          return i % 8 == 3 ? -1 : 0;
      }
    }

    test('rook on every square', () {
      for (int sq = 0; sq < 64; sq++) {
        for (int i = 0; i < 2000; i++) {
          final occ = occupancy(i);
          expect(sliders.rookAttacks(sq, occ), _naive(sq, occ, _orthogonal),
              reason: 'rook sq=${BoardHelper.squareName(sq)} occ=0x${occ.toRadixString(16)}');
        }
      }
    });

    test('bishop on every square', () {
      for (int sq = 0; sq < 64; sq++) {
        for (int i = 0; i < 2000; i++) {
          final occ = occupancy(i);
          expect(sliders.bishopAttacks(sq, occ), _naive(sq, occ, _diagonal),
              reason: 'bishop sq=${BoardHelper.squareName(sq)} occ=0x${occ.toRadixString(16)}');
        }
      }
    });

    test('queen on every square', () {
      for (int sq = 0; sq < 64; sq++) {
        for (int i = 0; i < 1000; i++) {
          final occ = occupancy(i);
          expect(sliders.queenAttacks(sq, occ), _naive(sq, occ, _orthogonal) | _naive(sq, occ, _diagonal),
              reason: 'queen sq=${BoardHelper.squareName(sq)} occ=0x${occ.toRadixString(16)}');
        }
      }
    });
  });
}
