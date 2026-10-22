import 'dart:collection';
import 'dart:typed_data';

import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/engines/v12/core/bitboard.dart';
import 'package:ace/engines/v12/core/game_state.dart';
import 'package:ace/engines/v12/core/move.dart';
import 'package:ace/engines/v12/core/piece.dart';
import 'package:ace/engines/v12/core/zobrist.dart';

class Board {
  bool whiteToPlay = true;
  int enPassantSquare = -1;
  bool whiteCastleKingSide = false;
  bool whiteCastleQueenSide = false;
  bool blackCastleKingSide = false;
  bool blackCastleQueenSide = false;
  List<GameState> gameStateHistory = [];
  int fiftyMoveRule = 0;
  HashMap<int, int> hashHistory = HashMap();
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

  Board() : this.fromFEN(FenPosition.startingPosition);

  Board.fromFEN(String fen) {
    FenPosition fenPosition = FenPosition.parse(fen);

    for (int i = 0; i < 64; i++) {
      int piece = fenPosition.position[i];
      if (piece != 0) _put(piece, i);
    }
    whiteToPlay = fenPosition.whiteToMove;
    enPassantSquare = fenPosition.enPassantSquare;
    whiteCastleKingSide = fenPosition.whiteCastleKingSide;
    whiteCastleQueenSide = fenPosition.whiteCastleQueenSide;
    blackCastleKingSide = fenPosition.blackCastleKingSide;
    blackCastleQueenSide = fenPosition.blackCastleQueenSide;

    castling = castlingRightsAsInt();
    epSquare = enPassantSquare;
    halfMove = fenPosition.halfmoveClock;

    zobristKey = Zobrist.getZobristForBoard(this);
    gameStateHistory = [];
    fiftyMoveRule = fenPosition.halfmoveClock;
    plyCount = (fenPosition.fullmoveNumber - 1) * 2 + (whiteToPlay ? 0 : 1);
    addMoveToHashHistory(zobristKey); // The starting position counts as seen once
  }

  makeMove(Move move) {
    // Set up current game state
    GameState gameState = GameState();
    gameState.whiteCastleKingSide = whiteCastleKingSide;
    gameState.whiteCastleQueenSide = whiteCastleQueenSide;
    gameState.blackCastleKingSide = blackCastleKingSide;
    gameState.blackCastleQueenSide = blackCastleQueenSide;
    gameState.zobristKey = zobristKey;

    // Who is moving to where
    int selectedPiece = squares[move.from];
    int capturedPiece = squares[move.to];
    int color = whiteToPlay ? Piece.white : Piece.black;

    // Save current state
    undoCaptured[plyCount] = capturedPiece;
    undoCastling[plyCount] = castlingRightsAsInt();
    undoEp[plyCount] = enPassantSquare;
    undoHalfMove[plyCount] = halfMove;
    keyStack[plyCount] = zobristKey;

    gameState.enPassantSquare = enPassantSquare;
    gameState.capturedPiece = capturedPiece;
    int startingCastlingIndex = castlingRightsAsInt();

    // Handle En passant file
    zobristKey ^= Zobrist.enPassantSquares[enPassantSquare + 1]; // Remove old enpassant square
    if (move.pawnTwoForward) {
      int direction = whiteToPlay ? -8 : 8;
      enPassantSquare = move.to - direction;
    } else {
      enPassantSquare = -1;
    }

    zobristKey ^= Zobrist.enPassantSquares[enPassantSquare + 1]; // Add new en passant square

    // Handle promotion

    // Handle captures
    if (move.enPassantCapture) {
      int capturedSq = move.to + (whiteToPlay ? 8 : -8);
      capturedPiece = squares[capturedSq];

      undoCaptured[plyCount] = capturedPiece;
      gameState.capturedPiece = capturedPiece;
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

      switch (castlingRank) {
        case 0:
          blackCastleQueenSide = false;
          blackCastleKingSide = false;
          break;
        case 7:
          whiteCastleKingSide = false;
          whiteCastleQueenSide = false;
          break;
        default:
          break;
      }
    } else if (Piece.type(selectedPiece) == Piece.king) {
      if (whiteToPlay) {
        whiteCastleKingSide = false;
        whiteCastleQueenSide = false;
      } else {
        blackCastleKingSide = false;
        blackCastleQueenSide = false;
      }
    } else if (Piece.type(selectedPiece) == Piece.rook) {
      if (whiteToPlay) {
        if (move.from == 56) {
          whiteCastleQueenSide = false;
        } else if (move.from == 63) {
          whiteCastleKingSide = false;
        }
      } else {
        if (move.from == 0) {
          blackCastleQueenSide = false;
        } else if (move.from == 7) {
          blackCastleKingSide = false;
        }
      }
    }
    if (Piece.type(capturedPiece) == Piece.rook) {
      if (Piece.isColor(capturedPiece, Piece.white)) {
        if (move.to == 56) {
          whiteCastleQueenSide = false;
        } else if (move.to == 63) {
          whiteCastleKingSide = false;
        }
      } else {
        if (move.to == 0) {
          blackCastleQueenSide = false;
        } else if (move.to == 7) {
          blackCastleKingSide = false;
        }
      }
    }

    int endingCastlingIndex = castlingRightsAsInt();
    if (startingCastlingIndex != endingCastlingIndex) {
      zobristKey ^= Zobrist.castlingRights[startingCastlingIndex];
      zobristKey ^= Zobrist.castlingRights[endingCastlingIndex];
    }
    // End of castling

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

    gameState.fiftyMoveRule = fiftyMoveRule;
    fiftyMoveRule++;
    plyCount++;
    halfMove++;
    if (Piece.type(selectedPiece) == Piece.pawn || Piece.type(capturedPiece) != Piece.none) {
      fiftyMoveRule = 0;
      halfMove = 0;
    }

    gameStateHistory.add(gameState);
    addMoveToHashHistory(zobristKey);
  }

  unMakeMove(Move move) {
    removeMoveFromHashHistory();
    plyCount--;
    halfMove = undoHalfMove[plyCount];

    int selectedPiece = squares[move.to]; // The piece at the end square of the move we are undo
    int color = whiteToPlay ? Piece.black : Piece.white; // The last move was the opposite of the current state
    int capturedPiece = gameStateHistory.last.capturedPiece;

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

      switch (castlingRank) {
        case 0:
          blackCastleQueenSide = gameStateHistory.last.blackCastleQueenSide;
          blackCastleKingSide = gameStateHistory.last.blackCastleKingSide;
          break;
        case 7:
          whiteCastleKingSide = gameStateHistory.last.whiteCastleKingSide;
          whiteCastleQueenSide = gameStateHistory.last.whiteCastleQueenSide;
          break;
        default:
          break;
      }
    } else if (Piece.type(selectedPiece) == Piece.king) {
      if (whiteToPlay) {
        // Opposite for undoing
        blackCastleQueenSide = gameStateHistory.last.blackCastleQueenSide;
        blackCastleKingSide = gameStateHistory.last.blackCastleKingSide;
      } else {
        whiteCastleKingSide = gameStateHistory.last.whiteCastleKingSide;
        whiteCastleQueenSide = gameStateHistory.last.whiteCastleQueenSide;
      }
    } else if (Piece.type(selectedPiece) == Piece.rook) {
      if (!whiteToPlay) {
        // Opposite because of previous go
        if (move.from == 56) {
          whiteCastleQueenSide = gameStateHistory.last.whiteCastleQueenSide;
        } else if (move.from == 63) {
          whiteCastleKingSide = gameStateHistory.last.whiteCastleKingSide;
        }
      } else {
        if (move.from == 0) {
          blackCastleQueenSide = gameStateHistory.last.blackCastleQueenSide;
        } else if (move.from == 7) {
          blackCastleKingSide = gameStateHistory.last.blackCastleKingSide;
        }
      }
    }
    if (Piece.type(capturedPiece) == Piece.rook) {
      if (Piece.isColor(capturedPiece, Piece.white)) {
        if (move.to == 56) {
          whiteCastleQueenSide = gameStateHistory.last.whiteCastleQueenSide;
        } else if (move.to == 63) {
          whiteCastleKingSide = gameStateHistory.last.whiteCastleKingSide;
        }
      } else {
        if (move.to == 0) {
          blackCastleQueenSide = gameStateHistory.last.blackCastleQueenSide;
        } else if (move.to == 7) {
          blackCastleKingSide = gameStateHistory.last.blackCastleKingSide;
        }
      }
    }

    // Handle en passant captures
    if (move.enPassantCapture) {
      int captureSq = move.to + (whiteToPlay ? -8 : 8);
      _put(capturedPiece, captureSq);
      capturedPiece = Piece.none;
    }

    enPassantSquare = gameStateHistory.last.enPassantSquare;

    fiftyMoveRule = gameStateHistory.last.fiftyMoveRule;

    gameStateHistory.removeLast();

    if (move.promotion == 0) _move(selectedPiece, move.to, move.from);
    if (capturedPiece != Piece.none) _put(capturedPiece, move.to);
    zobristKey = keyStack[plyCount];

    whiteToPlay = !whiteToPlay;
  }

  int castlingRightsAsInt() {
    int castlingIndex = 0;
    if (whiteCastleKingSide) castlingIndex |= 8;
    if (whiteCastleQueenSide) castlingIndex |= 4;
    if (blackCastleKingSide) castlingIndex |= 2;
    if (blackCastleQueenSide) castlingIndex |= 1;
    return castlingIndex;
  }

  void addMoveToHashHistory(int zobristHash) {
    hashHistory.update(zobristHash, (count) => count + 1, ifAbsent: () => 1);
  }

  void removeMoveFromHashHistory() {
    // Since the move is undone, decrement the count in the hash history.
    hashHistory.update(zobristKey, (count) => count - 1);
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
}
