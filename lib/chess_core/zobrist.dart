import 'dart:math';

import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/piece.dart';

/// Zobrist hashing keys. They are created on first use (once per isolate), so a board can never be
/// hashed with uninitialised all-zero keys.
class Zobrist {
  static final Random _random = Random(2024);

  // List for each type of piece and within that, each square on the board. Empty squares hash to 0.
  static final List<List<int>> piecesArray = List.generate(
    Piece.maxPieceIndex + 1,
    (piece) => List.generate(64, (index) => Piece.pieceList.contains(piece) ? generateRandom64BitNumber() : 0,
        growable: false),
    growable: false,
  );

  // There are 2^4 different possible castling combos, each needs a random number
  static final List<int> castlingRights = List.generate(16, (index) => generateRandom64BitNumber(), growable: false);

  // En passant square + 1, where index 0 means no en passant square
  static final List<int> enPassantSquares =
      List.generate(65, (index) => index == 0 ? 0 : generateRandom64BitNumber(), growable: false);

  // XORed in when it is black to move
  static final int sideToMove = generateRandom64BitNumber();

  static int getZobristForBoard(Board board) {
    int zobristkey = 0;

    // Pieces
    for (int index = 0; index < 64; index++) {
      int piece = board.position[index];
      zobristkey ^= piecesArray[piece][index];
    }

    // Castling
    zobristkey ^= castlingRights[board.castlingRightsAsInt()];

    // En Passant
    zobristkey ^= enPassantSquares[board.enPassantSquare + 1];

    // Side to move
    if (!board.whiteToPlay) zobristkey ^= sideToMove;

    return zobristkey;
  }

  static int generateRandom64BitNumber() {
    // Generate two 32-bit integers
    int part1 = _random.nextInt(1 << 32);
    int part2 = _random.nextInt(1 << 32);

    // Combine them to create a 64-bit number
    return (part1 << 32) | part2;
  }
}
