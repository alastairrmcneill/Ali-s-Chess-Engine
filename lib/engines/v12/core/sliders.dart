import 'dart:typed_data';

import 'package:ace/engines/v12/core/attack_tables.dart';
import 'package:ace/engines/v12/core/bitboard.dart';

// Direction indexes, matching the order used by AttackTables.rays (rays[sq * 8 + dir]).
const int _n = 0, _e = 1, _s = 2, _w = 3, _ne = 4, _se = 5, _sw = 6, _nw = 7;

class Sliders {
  final Uint64List _rays;

  Sliders(AttackTables tables) : _rays = tables.rays;

  int bishopAttacks(int sq, int occupied) {
    int attacks = 0;
    attacks |= _decreasing(sq, occupied, _ne);
    attacks |= _decreasing(sq, occupied, _nw);
    attacks |= _increasing(sq, occupied, _se);
    attacks |= _increasing(sq, occupied, _sw);
    return attacks;
  }

  int rookAttacks(int sq, int occupied) {
    int attacks = 0;
    attacks |= _decreasing(sq, occupied, _n);
    attacks |= _increasing(sq, occupied, _e);
    attacks |= _increasing(sq, occupied, _s);
    attacks |= _decreasing(sq, occupied, _w);
    return attacks;
  }

  int queenAttacks(int sq, int occupied) {
    int attacks = 0;
    attacks |= bishopAttacks(sq, occupied);
    attacks |= rookAttacks(sq, occupied);
    return attacks;
  }

  int _increasing(int sq, int occupied, int dir) {
    int attacks = _rays[sq * 8 + dir];
    int blockers = attacks & occupied;
    if (blockers != 0) {
      int firstBlocker = BitOps.lsb(blockers);
      attacks &= ~_rays[firstBlocker * 8 + dir];
    }
    return attacks;
  }

  int _decreasing(int sq, int occupied, int dir) {
    int attacks = _rays[sq * 8 + dir];
    int blockers = attacks & occupied;
    if (blockers != 0) {
      int firstBlocker = BitOps.msb(blockers);
      attacks &= ~_rays[firstBlocker * 8 + dir];
    }
    return attacks;
  }
}
