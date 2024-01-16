import 'dart:math';

import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/piece.dart';

class Zobrist {
  static final Random _random = Random();
  // List for each type of peice and within that, each square on the board
  static List<List<int>> piecesArray = List.generate(
    Piece.maxPieceIndex + 1,
    (index) => List.generate(64, (index) => 0, growable: false),
    growable: false,
  );

  // There are 2^4 different possible castling combos, each needs a random number
  static List<int> castlingRights = List.generate(16, (index) => 0, growable: false);

  // EnPassantSquare (need to include 0 for no enpassant square)
  static List<int> enPassantSquares = List.generate(65, (index) => 0, growable: false);

  // Side to move (0 for white, number for black)
  static int sideToMove = 0;

  Zobrist() {
    _init();
  }

  static int getZobristForBoard(Board board) {
    int zobristkey = 0;

    // Pieces
    for (int index = 0; index < 64; index++) {
      int piece = board.position[index];
      zobristkey ^= piecesArray[piece][index];
    }

    // Castling
    int castlingIndex = 0;
    if (board.whiteCastleKingSide) castlingIndex |= 8;
    if (board.whiteCastleQueenSide) castlingIndex |= 4;
    if (board.blackCastleKingSide) castlingIndex |= 2;
    if (board.blackCastleQueenSide) castlingIndex |= 1;

    zobristkey ^= castlingRights[castlingIndex];

    // En Passant
    zobristkey ^= enPassantSquares[board.enPassantSquare + 1];

    // Side to move
    if (!board.whiteToPlay) zobristkey ^= sideToMove;

    return zobristkey;
  }

  static _init() {
    // Setup piecesArray
    for (int piece in Piece.pieceList) {
      for (int index = 0; index < 64; index++) {
        piecesArray[piece][index] = generateRandom64BitNumber();
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
  }

  static int generateRandom64BitNumber() {
    // Generate two 32-bit integers
    int part1 = _random.nextInt(1 << 32);
    int part2 = _random.nextInt(1 << 32);

    // Combine them to create a 64-bit number
    return (part1 << 32) | part2;
  }
}
