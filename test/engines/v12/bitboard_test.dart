import 'dart:math';

import 'package:ace/engines/v12/core/bitboard.dart';
import 'package:flutter_test/flutter_test.dart';

int _naivePop(int b) {
  int n = 0;
  for (int i = 0; i < 64; i++) {
    if ((b >>> i) & 1 == 1) n++;
  }
  return n;
}

int _naiveLsb(int b) {
  for (int i = 0; i < 64; i++) {
    if ((b >>> i) & 1 == 1) return i;
  }
  return -1;
}

int _naiveMsb(int b) {
  for (int i = 63; i >= 0; i--) {
    if ((b >>> i) & 1 == 1) return i;
  }
  return -1;
}

int _bitsOf(List<int> squares) => squares.fold(0, (acc, s) => acc | (1 << s));

void main() {
  final rng = Random(12);
  int random64() => (rng.nextInt(1 << 32) << 32) | rng.nextInt(1 << 32);

  group('BitOps', () {
    test('popCount, lsb, msb match naive loops on random values', () {
      for (int i = 0; i < 10000; i++) {
        // Mix dense and sparse values.
        int b = random64();
        if (i % 3 == 1) b &= random64();
        if (i % 3 == 2) b &= random64() & random64();
        expect(BitOps.popCount(b), _naivePop(b));
        if (b != 0) {
          expect(BitOps.lsb(b), _naiveLsb(b));
          expect(BitOps.msb(b), _naiveMsb(b));
        }
      }
    });

    test('edge values', () {
      expect(BitOps.popCount(0), 0);
      expect(BitOps.popCount(-1), 64);
      for (int i = 0; i < 64; i++) {
        expect(BitOps.popCount(1 << i), 1);
        expect(BitOps.lsb(1 << i), i);
        expect(BitOps.msb(1 << i), i);
      }
      expect(BitOps.lsb(-1), 0);
      expect(BitOps.msb(-1), 63);
    });

    test('pop-lsb iteration visits each set bit in ascending order', () {
      int b = _bitsOf([0, 5, 31, 32, 63]);
      final seen = <int>[];
      while (b != 0) {
        seen.add(BitOps.lsb(b));
        b = BitOps.clearLsb(b);
      }
      expect(seen, [0, 5, 31, 32, 63]);
    });
  });

  group('constants', () {
    test('files and ranks', () {
      expect(BitOps.popCount(FILE_A), 8);
      expect(FILE_A & (1 << 56), isNonZero); // a1
      expect(FILE_H & (1 << 7), isNonZero); // h8
      expect(RANK_8 & (1 << 0), isNonZero); // a8
      expect(RANK_1 & (1 << 63), isNonZero); // h1
      expect(RANK_7, 0xFF << 8);
      expect(RANK_2, 0xFF << 48);
      expect(RANK_1 | RANK_2 | RANK_3 | RANK_4 | RANK_5 | RANK_6 | RANK_7 | RANK_8, -1);
    });

    test('light squares: a8 and h1 light, a1 and h8 dark', () {
      expect(BitOps.popCount(LIGHT_SQUARES), 32);
      expect(LIGHT_SQUARES & (1 << 0), isNonZero); // a8
      expect(LIGHT_SQUARES & (1 << 63), isNonZero); // h1
      expect(LIGHT_SQUARES & (1 << 56), isZero); // a1
      expect(LIGHT_SQUARES & (1 << 7), isZero); // h8
      for (int sq = 0; sq < 64; sq++) {
        final light = ((sq >> 3) + (sq & 7)) % 2 == 0;
        expect((LIGHT_SQUARES >>> sq) & 1, light ? 1 : 0, reason: 'sq $sq');
      }
    });
  });
}
