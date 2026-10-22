import 'dart:math';
import 'dart:typed_data';

import 'package:ace/engines/v12/core/board.dart';
import 'package:ace/engines/v12/core/piece.dart';

class Zobrist {
  static final Random _random = Random();

  // List for each type of peice and within that, each square on the board
  static final Int64List pieces = Int64List((Piece.maxPieceIndex + 1) * 64);

  // There are 2^4 different possible castling combos, each needs a random number
  static final Int64List castlingRights = Int64List(16);

  // EnPassantSquare (need to include 0 for no enpassant square)
  static final Int64List enPassantSquares = Int64List(65);

  // Side to move (0 for white, number for black)
  static int sideToMove = 0;

  Zobrist() {
    // Setup pieces
    for (int piece in Piece.pieceList) {
      for (int index = 0; index < 64; index++) {
        pieces[piece * 64 + index] = generateRandom64BitNumber();
      }
    }

    // Setup castling rights
    for (int i = 0; i < castlingRights.length; i++) {
      castlingRights[i] = generateRandom64BitNumber();
    }

    // Setup enpassant squares
    for (int i = 0; i < enPassantSquares.length; i++) {
      enPassantSquares[i] = i == 0 ? 0 : generateRandom64BitNumber();
    }

    // Setup
    sideToMove = generateRandom64BitNumber();
    _initialised = true;
  }

  static bool _initialised = false;

  /// The tables are static and all zero until a [Zobrist] is constructed. Call this before any Board is
  /// built so every key is real. Each isolate has its own statics, so each one needs this once.
  static void ensureInitialised() {
    if (!_initialised) Zobrist();
  }

  static int getZobristForBoard(Board board) {
    int zobristkey = 0;

    // Pieces
    for (int index = 0; index < 64; index++) {
      int piece = board.squares[index];
      zobristkey ^= pieces[piece * 64 + index];
    }

    // Castling
    zobristkey ^= castlingRights[board.castling];

    // En Passant
    zobristkey ^= enPassantSquares[board.epSquare + 1];

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
