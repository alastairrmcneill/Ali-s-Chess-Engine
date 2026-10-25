import 'dart:typed_data';

import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/engines/v12/core/attack_tables.dart';
import 'package:ace/engines/v12/core/bitboard.dart';
import 'package:ace/engines/v12/core/move.dart';
import 'package:ace/engines/v12/core/piece.dart';
import 'package:ace/engines/v12/core/sliders.dart';
import 'package:ace/engines/v12/core/zobrist.dart';

class Board {
  bool whiteToPlay = true;
  int plyCount = 0;
  int zobristKey = 0;
  final Uint64List pieceBB = Uint64List(16); // indexed by piece code (e.g. Piece.whiteKnight)
  final Uint64List colourBB = Uint64List(2); // 0 white, 1 black
  final Uint8List squares = Uint8List(64); // mailbox, kept in sync for O(1) piece-on-square
  int castling = 0;
  int epSquare = -1 /* -1 none */;
  int halfMove = 0;
  // Undo stack, preallocated (MAX_GAME_PLY = 2048: 300-move game + search depth + margin)
  final Int64List keyStack = Int64List(2048);
  final Int32List undoCaptured = Int32List(2048);
  final Int32List undoCastling = Int32List(2048);
  final Int32List undoEp = Int32List(2048);
  final Int32List undoHalfMove = Int32List(2048);
  static final AttackTables _tables = AttackTables();
  static final Sliders _sliders = Sliders(_tables);
  static final Int32List _castleMask = _tables.castleMask;

  Board() : this.fromFEN(FenPosition.startingPosition);

  Board.fromFEN(String fen) {
    FenPosition fenPosition = FenPosition.parse(fen);

    for (int i = 0; i < 64; i++) {
      int piece = fenPosition.position[i];
      if (piece != 0) _put(piece, i);
    }
    whiteToPlay = fenPosition.whiteToMove;

    castling |= fenPosition.whiteCastleKingSide ? 8 : 0;
    castling |= fenPosition.whiteCastleQueenSide ? 4 : 0;
    castling |= fenPosition.blackCastleKingSide ? 2 : 0;
    castling |= fenPosition.blackCastleQueenSide ? 1 : 0;

    epSquare = fenPosition.enPassantSquare;
    halfMove = fenPosition.halfmoveClock;

    zobristKey = Zobrist.getZobristForBoard(this);
    plyCount = (fenPosition.fullmoveNumber - 1) * 2 + (whiteToPlay ? 0 : 1);
  }

  makeMove(Move move) {
    // Who is moving to where
    int selectedPiece = squares[move.from];
    int capturedPiece = squares[move.to];
    int color = whiteToPlay ? Piece.white : Piece.black;

    // Save current state
    undoCaptured[plyCount] = capturedPiece;
    undoCastling[plyCount] = castling;
    undoEp[plyCount] = epSquare;
    undoHalfMove[plyCount] = halfMove;
    keyStack[plyCount] = zobristKey;

    // Handle En passant file
    zobristKey ^= Zobrist.enPassantSquares[epSquare + 1]; // Remove old enpassant square
    if (move.pawnTwoForward) {
      int direction = whiteToPlay ? -8 : 8;
      epSquare = move.to - direction;
    } else {
      epSquare = -1;
    }

    zobristKey ^= Zobrist.enPassantSquares[epSquare + 1]; // Add new en passant square

    // Handle captures
    if (move.enPassantCapture) {
      int capturedSq = move.to + (whiteToPlay ? 8 : -8);
      capturedPiece = squares[capturedSq];

      undoCaptured[plyCount] = capturedPiece;
      _remove(capturedPiece, capturedSq);
    } else if (capturedPiece != Piece.none) {
      _remove(capturedPiece, move.to);
    }

    // Castling
    if (move.castling) {
      int castlingRank = whiteToPlay ? 7 : 0;
      int rookStartingIndex = move.to % 8 == 2 ? castlingRank * 8 + 0 : castlingRank * 8 + 7;
      int rookTargetIndex = move.to % 8 == 2 ? castlingRank * 8 + 3 : castlingRank * 8 + 5;

      _move(Piece.rook | color, rookStartingIndex, rookTargetIndex);
    }
    int newCastling = castling & _castleMask[move.from] & _castleMask[move.to];

    if (newCastling != castling) {
      zobristKey ^= Zobrist.castlingRights[castling];
      zobristKey ^= Zobrist.castlingRights[newCastling];
      castling = newCastling;
    }

    // Update positions
    if (move.promotion != 0) {
      _remove(selectedPiece, move.from);
      selectedPiece = move.promotingPiece() | color;
      _put(selectedPiece, move.to);
    } else {
      _move(selectedPiece, move.from, move.to);
    }

    // Swap sides
    whiteToPlay = !whiteToPlay;
    zobristKey ^= Zobrist.sideToMove;

    plyCount++;
    halfMove++;
    if (move.promotion != 0 || Piece.type(selectedPiece) == Piece.pawn || Piece.type(capturedPiece) != Piece.none) {
      halfMove = 0;
    }
  }

  unMakeMove(Move move) {
    plyCount--;
    halfMove = undoHalfMove[plyCount];
    castling = undoCastling[plyCount];
    epSquare = undoEp[plyCount];

    int selectedPiece = squares[move.to]; // The piece at the end square of the move we are undo
    int color = whiteToPlay ? Piece.black : Piece.white; // The last move was the opposite of the current state
    int capturedPiece = undoCaptured[plyCount];

    // Handle promotion
    if (move.promotion != 0) {
      _remove(selectedPiece, move.to);
      selectedPiece = Piece.pawn | color;
      _put(selectedPiece, move.from);
    }

    // Handle castles
    if (move.castling) {
      int castlingRank = whiteToPlay ? 0 : 7; // other way round
      int rookStartingIndex = move.to % 8 == 2 ? castlingRank * 8 + 0 : castlingRank * 8 + 7;
      int rookTargetIndex = move.to % 8 == 2 ? castlingRank * 8 + 3 : castlingRank * 8 + 5;

      _move(Piece.rook | color, rookTargetIndex, rookStartingIndex);
    }

    // Handle en passant captures
    if (move.enPassantCapture) {
      int captureSq = move.to + (whiteToPlay ? -8 : 8);
      _put(capturedPiece, captureSq);
      capturedPiece = Piece.none;
    }

    if (move.promotion == 0) _move(selectedPiece, move.to, move.from);
    if (capturedPiece != Piece.none) _put(capturedPiece, move.to);
    zobristKey = keyStack[plyCount];

    whiteToPlay = !whiteToPlay;
  }

  @pragma('vm:prefer-inline')
  void _put(int piece, int sq) {
    squares[sq] = piece;
    zobristKey ^= Zobrist.pieces[piece * 64 + sq];
    pieceBB[piece] |= 1 << sq;
    if (Piece.isColor(piece, Piece.white)) {
      colourBB[0] |= 1 << sq;
    } else {
      colourBB[1] |= 1 << sq;
    }
  }

  @pragma('vm:prefer-inline')
  void _remove(int piece, int sq) {
    squares[sq] = 0;
    zobristKey ^= Zobrist.pieces[piece * 64 + sq];
    pieceBB[piece] &= ~(1 << sq);

    if (Piece.isColor(piece, Piece.white)) {
      colourBB[0] &= ~(1 << sq);
    } else {
      colourBB[1] &= ~(1 << sq);
    }
  }

  @pragma('vm:prefer-inline')
  void _move(int piece, int from, int to) {
    squares[from] = 0;
    squares[to] = piece;
    zobristKey ^= Zobrist.pieces[piece * 64 + from] ^ Zobrist.pieces[piece * 64 + to];
    int mask = (1 << from) | (1 << to);
    pieceBB[piece] ^= mask;
    if (Piece.isColor(piece, Piece.white)) {
      colourBB[0] ^= mask;
    } else {
      colourBB[1] ^= mask;
    }
  }

  bool isRepetition() {
    final oldest = plyCount - halfMove;
    for (int i = plyCount - 2; i >= oldest && i >= 0; i -= 2) {
      if (keyStack[i] == zobristKey) return true;
    }
    return false;
  }

  int kingSquare(int color) {
    return BitOps.lsb(pieceBB[Piece.king | color]);
  }

  int attackersOfSquare(int sq, int occupied, int attacker) {
    int defender = 1 - attacker;
    int attackingColour = attacker * 8;

    int attackingQueens = pieceBB[(Piece.queen | attackingColour)];
    int attackingRooks = pieceBB[(Piece.rook | attackingColour)];
    int attackingBishops = pieceBB[(Piece.bishop | attackingColour)];
    int attackingKnights = pieceBB[(Piece.knight | attackingColour)];
    int attackingPawns = pieceBB[(Piece.pawn | attackingColour)];
    int attackingKing = pieceBB[(Piece.king | attackingColour)];

    // Pawn logic: white king on e1 (sq 60), attacker = 1 (black), so defender = 0 (white).
    // - pawnAttacks[0 * 64 + 60] is a white pawn's attacks from e1, which are d2 and f2.
    // - A black pawn on d2 or f2 attacks e1, so & blackPawns finds it.

    // Checkers
    return (_tables.knightAttacks[sq] & attackingKnights) |
        (_tables.kingAttacks[sq] & attackingKing) |
        (_tables.pawnAttacks[defender * 64 + sq] & attackingPawns) |
        _sliders.rookAttacks(sq, occupied) & (attackingRooks | attackingQueens) |
        _sliders.bishopAttacks(sq, occupied) & (attackingBishops | attackingQueens);
  }

  bool isInCheck() {
    int us = whiteToPlay ? 0 : 1;
    int ksq = kingSquare(us * 8);
    int attackers = attackersOfSquare(ksq, colourBB[0] | colourBB[1], 1 - us);
    return attackers != 0;
  }
}
