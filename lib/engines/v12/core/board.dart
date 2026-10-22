import 'dart:collection';
import 'dart:typed_data';

import 'package:ace/chess_core/notation/fen.dart';
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
  int halfmove = 0;
// Undo stack, preallocated (MAX_GAME_PLY = 2048: 300-move game + search depth + margin)
  final Int64List keyStack = Int64List(2048);
  final Int32List undoCaptured = Int32List(2048);
  final Int32List undoCastling = Int32List(2048);
  final Int32List undoEp = Int32List(2048);
  final Int32List undoHalfmove = Int32List(2048);

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
    halfmove = fenPosition.halfmoveClock;

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

    gameState.enPassantSquare = enPassantSquare;
    gameState.capturedPiece = capturedPiece;
    int startingCastlingIndex = castlingRightsAsInt();

    // Remove selected piece from start square zobrist
    zobristKey ^= Zobrist.piecesArray[selectedPiece][move.from]; // Remove starting peice from starting square

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
    if (move.promotion != 0) {
      selectedPiece = move.promotingPiece() | color;
    }

    // Handle en passant captures
    if (move.enPassantCapture) {
      int direction = whiteToPlay ? 8 : -8;
      int enPassantCaptureSquare = move.to + direction;

      zobristKey ^= Zobrist.piecesArray[squares[enPassantCaptureSquare]]
          [enPassantCaptureSquare]; // Remove en passant capture square from zobrist
      gameState.capturedPiece = squares[enPassantCaptureSquare];
      squares[enPassantCaptureSquare] = 0;
    }

    // Castling
    if (move.castling) {
      int castlingRank = whiteToPlay ? 7 : 0;
      int rookStartingIndex = move.to % 8 == 2 ? castlingRank * 8 + 0 : castlingRank * 8 + 7;
      int rookTargetIndex = move.to % 8 == 2 ? castlingRank * 8 + 3 : castlingRank * 8 + 5;

      squares[rookTargetIndex] = squares[rookStartingIndex];
      squares[rookStartingIndex] = 0;
      zobristKey ^= Zobrist.piecesArray[squares[rookTargetIndex]][rookStartingIndex];
      zobristKey ^= Zobrist.piecesArray[squares[rookTargetIndex]][rookTargetIndex];

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
    squares[move.to] = selectedPiece;
    squares[move.from] = 0;

    zobristKey ^= Zobrist.piecesArray[capturedPiece][move.to]; // Remove piece from target square
    zobristKey ^= Zobrist.piecesArray[selectedPiece][move.to]; // Add starting piece to target square

    // Swap sides
    whiteToPlay = !whiteToPlay;
    zobristKey ^= Zobrist.sideToMove;

    gameState.fiftyMoveRule = fiftyMoveRule;
    fiftyMoveRule++;
    if (Piece.type(selectedPiece) == Piece.pawn || Piece.type(capturedPiece) != Piece.none) {
      fiftyMoveRule = 0;
    }

    gameStateHistory.add(gameState);
    addMoveToHashHistory(zobristKey);
  }

  unMakeMove(Move move) {
    int selectedPiece = squares[move.to]; // The piece at the end square of the move we are undo
    int color = whiteToPlay ? Piece.black : Piece.white; // The last move was the opposite of the current state
    int capturedPiece = gameStateHistory.last.capturedPiece;

    // Handle promotion
    if (move.promotion != 0) {
      selectedPiece = Piece.pawn | color;
    }

    // Handle castles
    if (move.castling) {
      int castlingRank = whiteToPlay ? 0 : 7; // other way round
      int rookStartingIndex = move.to % 8 == 2 ? castlingRank * 8 + 0 : castlingRank * 8 + 7;
      int rookTargetIndex = move.to % 8 == 2 ? castlingRank * 8 + 3 : castlingRank * 8 + 5;

      squares[rookStartingIndex] = squares[rookTargetIndex];
      squares[rookTargetIndex] = 0;

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
      int direction = whiteToPlay ? -8 : 8; // The last move was the opposite of the current state
      int enPassantCaptureSquare = move.to + direction;

      squares[enPassantCaptureSquare] = capturedPiece;
      capturedPiece = 0;
      enPassantSquare = move.to;
    }

    enPassantSquare = gameStateHistory.last.enPassantSquare;

    fiftyMoveRule = gameStateHistory.last.fiftyMoveRule;

    removeMoveFromHashHistory();
    zobristKey = gameStateHistory.last.zobristKey;
    gameStateHistory.removeLast();

    squares[move.from] = selectedPiece;
    squares[move.to] = capturedPiece;
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
    zobristKey ^= Zobrist.piecesArray[piece][sq];
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
    zobristKey ^= Zobrist.piecesArray[piece][sq];
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
    zobristKey ^= Zobrist.piecesArray[piece][from] ^ Zobrist.piecesArray[piece][to];
    int mask = (1 << from) | (1 << to);
    pieceBB[piece] ^= mask;
    if (Piece.isColor(piece, Piece.white)) {
      colourBB[0] ^= mask;
    } else {
      colourBB[1] ^= mask;
    }
  }
}
