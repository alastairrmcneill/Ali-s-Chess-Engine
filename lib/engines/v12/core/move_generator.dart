import 'dart:typed_data';

import 'package:ace/engines/v12/core/attack_tables.dart';
import 'package:ace/engines/v12/core/bitboard.dart';
import 'package:ace/engines/v12/core/board.dart';
import 'package:ace/engines/v12/core/move.dart';
import 'package:ace/engines/v12/core/piece.dart';
import 'package:ace/engines/v12/core/sliders.dart';

class MoveGenerator {
  List<Move> moves = [];
  static final AttackTables a = AttackTables();
  static final Sliders s = Sliders(a);

  // Debug values from the last generate() call, shown by the Generator tab next to a naive reference.
  // null = not computed yet. Assign each one when you implement its step, then leave them in (they are cheap).
  int? lastCheckers; // step 3: bitboard of pieces giving check
  int? lastCheckMask; // step 5: -1 when not in check, else between | checkers
  int? lastPinned; // step 6: bitboard of our pinned pieces
  final Uint64List _pinRay = Uint64List(64);

  MoveGenerator();

  List<Move> generate(Board board, {bool capturesOnly = false}) {
    moves = [];
    lastCheckers = lastCheckMask = lastPinned = null;

    // Setup
    int us = board.whiteToPlay ? 0 : 1;
    int them = board.whiteToPlay ? 1 : 0;
    int ourC = us * 8;
    int theirC = them * 8;
    int ourBB = board.colourBB[us];
    int theirBB = board.colourBB[them];
    int occ = ourBB | theirBB;
    int ksq = BitOps.lsb(board.pieceBB[(Piece.king | ourC)]);
    int ksqBit = 1 << ksq;

    int theirQueens = board.pieceBB[(Piece.queen | theirC)];
    int theirRooks = board.pieceBB[(Piece.rook | theirC)];
    int theirBishops = board.pieceBB[(Piece.bishop | theirC)];
    int theirRQ = theirRooks | theirQueens;
    int theirBQ = theirBishops | theirQueens;
    int theirKnights = board.pieceBB[(Piece.knight | theirC)];
    int theirPawns = board.pieceBB[(Piece.pawn | theirC)];

    // Checks
    int checkers = (a.knightAttacks[ksq] & theirKnights) |
        (a.pawnAttacks[us * 64 + ksq] & theirPawns) |
        s.rookAttacks(ksq, occ) & theirRQ |
        s.bishopAttacks(ksq, occ) & theirBQ;

    lastCheckers = checkers;
    bool inCheck = checkers != 0;
    // Subtracting 1 from a bitboard and ANDing with itself checks if more than one bit is set
    bool inDoubleCheck = (checkers & (checkers - 1)) != 0;

    // King Moves
    int kingTargets = a.kingAttacks[ksq] & ~ourBB;

    if (capturesOnly) kingTargets &= theirBB;
    final occNoKing = occ ^ ksqBit;

    while (kingTargets != 0) {
      final to = BitOps.lsb(kingTargets);
      kingTargets &= kingTargets - 1;

      if (board.attackersOfSquare(to, occNoKing, them) == 0) {
        moves.add(Move.encode(ksq, to));
      }
    }

    if (inDoubleCheck) return moves;

    // Check mask
    int checkMask = -1; // Every square is availble
    if (inCheck) {
      // Are there any squares between king and checker?
      // Add those to the mask, or just add the chcker if its a pawn or knight attacker
      int checker = BitOps.lsb(checkers); // Get the square of the checking piece
      checkMask = a.between[ksq * 64 + checker] | checkers;
    }
    lastCheckMask = checkMask;

    // Pins
    _pinRay.fillRange(0, 64, 0); // Clear the pin rays for this move generation

    int snipers = s.rookAttacks(ksq, 0) & theirRQ | s.bishopAttacks(ksq, 0) & theirBQ;

    int pinned = 0;
    while (snipers != 0) {
      final sniper = BitOps.lsb(snipers);
      snipers &= snipers - 1;

      int between = a.between[ksq * 64 + sniper];

      int blockers = between & occ;

      // Exactly 1 piece in the way and its ours then it is pinned
      if (blockers != 0 && (blockers & (blockers - 1)) == 0 && (blockers & ourBB) != 0) {
        pinned |= blockers;

        // The piece on that square can only move along the line or capture the sniper
        _pinRay[BitOps.lsb(blockers)] = between | (1 << sniper);
      }
    }

    lastPinned = pinned;

    // Knight moves
    int targets = ~ourBB & checkMask;

    if (capturesOnly) targets &= theirBB;

    int knights = board.pieceBB[(Piece.knight | ourC)] & ~pinned;

    while (knights != 0) {
      int from = BitOps.lsb(knights);
      knights &= knights - 1;

      _addMoves(from, a.knightAttacks[from] & targets);
    }

    // Slider moves

    _sliderMoves(board.pieceBB[(Piece.bishop | ourC)], s.bishopAttacks, occ, targets, pinned);
    _sliderMoves(board.pieceBB[(Piece.rook | ourC)], s.rookAttacks, occ, targets, pinned);
    _sliderMoves(board.pieceBB[(Piece.queen | ourC)], s.queenAttacks, occ, targets, pinned);

    // Pawn moves
    int dir = us == 0 ? -8 : 8;
    int startRank = us == 0 ? 6 : 1;
    int promoRank = us == 0 ? 1 : 6;

    int ourPawns = board.pieceBB[(Piece.pawn | ourC)];

    while (ourPawns != 0) {
      int from = BitOps.lsb(ourPawns);
      ourPawns &= ourPawns - 1;

      int rank = from >> 3;

      int allowed = checkMask & (((pinned >>> from) & 1) == 1 ? _pinRay[from] : -1);

      if (!capturesOnly) {
        int one = from + dir;
        // Check if the one push is not occupied
        if ((occ >>> one) & 1 == 0) {
          if ((allowed >>> one) & 1 == 1) {
            rank == promoRank ? _promotions(from, one) : moves.add(Move.encode(from, one));
          }
          if (rank == startRank) {
            int two = from + 2 * dir;
            if ((occ >>> two) & 1 == 0 && (allowed >>> two) & 1 == 1) {
              moves.add(Move.encode(from, two, 3)); // flag 3 = double push
            }
          }
        }
      }

      int captures = a.pawnAttacks[us * 64 + from] & theirBB & allowed;

      while (captures != 0) {
        int to = BitOps.lsb(captures);
        captures &= captures - 1;
        rank == promoRank ? _promotions(from, to) : moves.add(Move.encode(from, to));
      }
    }

    // En passant
    int ep = board.epSquare;
    if (ep >= 0) {
      int captureSq = ep + (us == 0 ? 8 : -8);

      int attackers = a.pawnAttacks[them * 64 + ep] & board.pieceBB[(Piece.pawn | ourC)];

      while (attackers != 0) {
        int from = BitOps.lsb(attackers);
        attackers &= attackers - 1;

        int occ2 = (occ ^ (1 << from) ^ (1 << captureSq) | (1 << ep));
        int theirPawnsAfter = theirPawns & ~(1 << captureSq);

        int attacked = (a.knightAttacks[ksq] & theirKnights) |
            (a.pawnAttacks[us * 64 + ksq] & theirPawnsAfter) |
            s.rookAttacks(ksq, occ2) & (theirRooks | theirQueens) |
            s.bishopAttacks(ksq, occ2) & (theirBishops | theirQueens);

        if (attacked == 0) moves.add(Move.encode(from, ep, 1));
      }
    }

    // Castling
    if (!inCheck && !capturesOnly) {
      int base = us == 0 ? 56 : 0;

      // If kight is on its home square
      if (ksq == base + 4) {
        int kingSideRight = us == 0 ? 8 : 2;
        int queenSideRight = us == 0 ? 4 : 1;

        if (board.castling & kingSideRight != 0 &&
            occ & ((1 << (base + 5)) | (1 << (base + 6))) == 0 &&
            board.attackersOfSquare(base + 5, occ, them) == 0 &&
            board.attackersOfSquare(base + 6, occ, them) == 0) {
          moves.add(Move.encode(ksq, base + 6, 2)); // flag 2 = king-side castling
        }
        if (board.castling & queenSideRight != 0 &&
            occ & ((1 << (base + 1)) | (1 << (base + 2)) | (1 << (base + 3))) == 0 &&
            board.attackersOfSquare(base + 2, occ, them) == 0 &&
            board.attackersOfSquare(base + 3, occ, them) == 0) {
          moves.add(Move.encode(ksq, base + 2, 2)); // flag 2 = queen-side castling
        }
      }
    }

    return moves;
  }

  void _addMoves(int from, int attacks) {
    while (attacks != 0) {
      int to = BitOps.lsb(attacks);
      attacks &= attacks - 1;
      moves.add(Move.encode(from, to));
    }
  }

  void _sliderMoves(int bb, int Function(int sq, int occ) attacksFor, int occ, int targets, int pinned) {
    while (bb != 0) {
      int from = BitOps.lsb(bb);
      bb &= bb - 1;

      int attacks = attacksFor(from, occ) & targets;

      if ((pinned >>> from) & 1 == 1) {
        // Is this a pinned piece
        attacks &= _pinRay[from]; // Limit the moves to the pin ray
      }
      _addMoves(from, attacks);
    }
  }

  void _promotions(int from, int to) {
    for (int flag = 4; flag <= 7; flag++) {
      // 4 Q, 5 N, 6 R, 7 B
      moves.add(Move.encode(from, to, flag));
    }
  }
}
