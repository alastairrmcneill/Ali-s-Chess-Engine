// ignore_for_file: constant_identifier_names

// Bitboard constants and bit utilities.
// Square mapping: bit i = square i, index 0 = a8, 63 = h1 (rank 8 first).
// North (towards rank 8) is >>> 8, south is << 8, east is << 1, west is >>> 1.
//
// Always use >>> (logical shift), never >>: bitboards with bit 63 set are negative ints.

const int FILE_A = 0x0101010101010101;
const int FILE_B = FILE_A << 1;
const int FILE_G = FILE_A << 6;
const int FILE_H = FILE_A << 7;

const int RANK_8 = 0xFF;
const int RANK_7 = RANK_8 << 8;
const int RANK_6 = RANK_8 << 16;
const int RANK_5 = RANK_8 << 24;
const int RANK_4 = RANK_8 << 32;
const int RANK_3 = RANK_8 << 40;
const int RANK_2 = RANK_8 << 48;
const int RANK_1 = RANK_8 << 56;

// Squares where (rank row + file) is even in this mapping (a8 and h1 are light).
const int LIGHT_SQUARES = 0xAA55AA55AA55AA55;
const int DARK_SQUARES = ~LIGHT_SQUARES;

const int ALL_SQUARES = -1;

class BitOps {
  BitOps._();

  static const int _deBruijn = 0x03f79d71b4cb0a89;

  // Maps the top 6 bits of (isolatedBit * _deBruijn) to the bit index.
  static final List<int> _index64 = _buildIndex64();

  static List<int> _buildIndex64() {
    final table = List<int>.filled(64, 0);
    for (int i = 0; i < 64; i++) {
      table[((1 << i) * _deBruijn) >>> 58] = i;
    }
    return table;
  }

  static int bit(int sq) => 1 << sq;

  @pragma('vm:prefer-inline')
  static int popCount(int b) {
    b = b - ((b >>> 1) & 0x5555555555555555);
    b = (b & 0x3333333333333333) + ((b >>> 2) & 0x3333333333333333);
    b = (b + (b >>> 4)) & 0x0F0F0F0F0F0F0F0F;
    return (b * 0x0101010101010101) >>> 56;
  }

  /// Index of the lowest set bit. [b] must be non-zero.
  @pragma('vm:prefer-inline')
  static int lsb(int b) => _index64[((b & -b) * _deBruijn) >>> 58];

  /// Index of the highest set bit. [b] must be non-zero.
  @pragma('vm:prefer-inline')
  static int msb(int b) {
    b |= b >>> 1;
    b |= b >>> 2;
    b |= b >>> 4;
    b |= b >>> 8;
    b |= b >>> 16;
    b |= b >>> 32;
    return _index64[((b - (b >>> 1)) * _deBruijn) >>> 58];
  }

  /// Clears the lowest set bit.
  @pragma('vm:prefer-inline')
  static int clearLsb(int b) => b & (b - 1);

  /// Debug printer: rank 8 at the top, a-file on the left.
  static String toAscii(int b) {
    final sb = StringBuffer();
    for (int rank = 0; rank < 8; rank++) {
      sb.write('${8 - rank} ');
      for (int file = 0; file < 8; file++) {
        sb.write((b >>> (rank * 8 + file)) & 1 == 1 ? 'X ' : '. ');
      }
      sb.writeln();
    }
    sb.write('  a b c d e f g h');
    return sb.toString();
  }
}
