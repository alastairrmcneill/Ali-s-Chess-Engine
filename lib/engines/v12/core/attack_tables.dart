import 'dart:typed_data';

const List<int> _dirRank = [-1, 0, 1, 0, -1, 1, 1, -1];
const List<int> _dirFile = [0, 1, 0, -1, 1, 1, -1, -1];

class AttackTables {
  Uint64List kingAttacks = Uint64List(64);
  Uint64List knightAttacks = Uint64List(64);
  Uint64List pawnAttacks = Uint64List(128);
  Uint64List rays = Uint64List(8 * 64);
  Uint64List between = Uint64List(64 * 64);
  Uint64List line = Uint64List(64 * 64);
  Int32List castleMask = Int32List(64)..fillRange(0, 64, 15);

  AttackTables() {
    _generateKingAttacks();
    _generateKnightAttacks();
    _generatePawnAttacks();
    _generateRays();
    _generateBetween();
    _generateLine();
    _generateCastleMask();
  }

  int _sqBit(int rank, int file) {
    if (rank < 0 || rank > 7 || file < 0 || file > 7) {
      return 0;
    }
    return 1 << (rank * 8 + file);
  }

  _generateKingAttacks() {
    List<int> kingRankOffsets = [-1, -1, -1, 0, 0, 1, 1, 1];
    List<int> kingFileOffsets = [-1, 0, 1, -1, 1, -1, 0, 1];
    for (int sq = 0; sq < 64; sq++) {
      int rank = sq >> 3;
      int file = sq & 7;

      int target = 0;
      for (int i = 0; i < kingRankOffsets.length; i++) {
        int targetRank = rank + kingRankOffsets[i];
        int targetFile = file + kingFileOffsets[i];
        target |= _sqBit(targetRank, targetFile);
      }
      kingAttacks[sq] = target;
    }
  }

  _generateKnightAttacks() {
    List<int> knightRankOffsets = [2, 2, 1, -1, -2, -2, -1, 1];
    List<int> knightFileOffsets = [-1, 1, 2, 2, 1, -1, -2, -2];
    for (int sq = 0; sq < 64; sq++) {
      int rank = sq >> 3;
      int file = sq & 7;

      int target = 0;
      for (int i = 0; i < knightRankOffsets.length; i++) {
        int targetRank = rank + knightRankOffsets[i];
        int targetFile = file + knightFileOffsets[i];
        target |= _sqBit(targetRank, targetFile);
      }
      knightAttacks[sq] = target;
    }
  }

  _generatePawnAttacks() {
    for (int sq = 0; sq < 64; sq++) {
      int rank = sq >> 3;
      int file = sq & 7;

      // White pawn attacks
      int targetRight = _sqBit(rank - 1, file + 1);
      int targetLeft = _sqBit(rank - 1, file - 1);
      pawnAttacks[sq] = targetRight | targetLeft;

      // Black pawn attacks
      targetRight = _sqBit(rank + 1, file + 1);
      targetLeft = _sqBit(rank + 1, file - 1);
      pawnAttacks[64 + sq] = targetRight | targetLeft;
    }
  }

  _generateRays() {
    for (int sq = 0; sq < 64; sq++) {
      int rank = sq >> 3;
      int file = sq & 7;

      for (int dir = 0; dir < _dirRank.length; dir++) {
        int targetRank = rank + _dirRank[dir];
        int targetFile = file + _dirFile[dir];

        int target = 0;

        while (targetRank >= 0 && targetRank <= 7 && targetFile >= 0 && targetFile <= 7) {
          target |= _sqBit(targetRank, targetFile);
          targetRank += _dirRank[dir];
          targetFile += _dirFile[dir];
        }
        rays[sq * _dirRank.length + dir] = target;
      }
    }
  }

  _generateBetween() {
    for (int sq1 = 0; sq1 < 64; sq1++) {
      int rank1 = sq1 >> 3;
      int file1 = sq1 & 7;

      for (int sq2 = 0; sq2 < 64; sq2++) {
        int rank2 = sq2 >> 3;
        int file2 = sq2 & 7;

        int deltaRank = rank2 - rank1;
        int deltaFile = file2 - file1;

        if (deltaFile == 0 || deltaRank == 0 || deltaFile.abs() == deltaRank.abs()) {
          int stepRank = deltaRank == 0 ? 0 : deltaRank ~/ deltaRank.abs();
          int stepFile = deltaFile == 0 ? 0 : deltaFile ~/ deltaFile.abs();

          int targetRank = rank1 + stepRank;
          int targetFile = file1 + stepFile;

          int b = 0;
          while (targetRank != rank2 || targetFile != file2) {
            b |= _sqBit(targetRank, targetFile);
            targetRank += stepRank;
            targetFile += stepFile;
          }
          between[sq1 * 64 + sq2] = b;
        }
      }
    }
  }

  _generateLine() {
    for (int sq1 = 0; sq1 < 64; sq1++) {
      int rank1 = sq1 >> 3;
      int file1 = sq1 & 7;

      for (int sq2 = 0; sq2 < 64; sq2++) {
        int rank2 = sq2 >> 3;
        int file2 = sq2 & 7;

        int deltaRank = rank2 - rank1;
        int deltaFile = file2 - file1;

        if (deltaFile == 0 || deltaRank == 0 || deltaFile.abs() == deltaRank.abs()) {
          int stepRank = deltaRank == 0 ? 0 : deltaRank ~/ deltaRank.abs();
          int stepFile = deltaFile == 0 ? 0 : deltaFile ~/ deltaFile.abs();

          int targetRank = rank1 + stepRank;
          int targetFile = file1 + stepFile;

          int l = 0;
          while (targetRank != rank2 || targetFile != file2) {
            l |= _sqBit(targetRank, targetFile);
            targetRank += stepRank;
            targetFile += stepFile;
          }
          l |= _sqBit(rank2, file2);
          l |= _sqBit(rank1, file1);
          line[sq1 * 64 + sq2] = l;
        }
      }
    }
  }

  _generateCastleMask() {
    // If anything touches those squares then we'll loose some castling rights.
    // &= ~ notation means we are ANDing a mask which has the number after the ~ removedd
    // 8 - 1000 - White kingside castle available
    // 4 - 0100 - White queenside castle available
    // 2 - 0010 - Black kingside castle available
    // 1 - 0001 - Black queenside castle available
    // Add them together gets 15 so if we touch another square on the board
    // Then it doesn't impact the castling rights.

    castleMask[56] &= ~4;
    castleMask[63] &= ~8;
    castleMask[60] &= ~12;
    castleMask[0] &= ~1;
    castleMask[7] &= ~2;
    castleMask[4] &= ~3;
  }
}
