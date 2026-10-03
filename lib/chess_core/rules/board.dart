import 'dart:collection';

import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/rules/game_state.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/zobrist.dart';

class Board {
  late List<int> position;
  late bool whiteToPlay;
  late int enPassantSquare;
  late bool whiteCastleKingSide;
  late bool whiteCastleQueenSide;
  late bool blackCastleKingSide;
  late bool blackCastleQueenSide;
  late List<GameState> gameStateHistory;
  late int fiftyMoveRule;
  late HashMap<int, int> hashHistory = HashMap();
  late int plyCount;
  late int zobristKey;

  Board() : this.fromFEN(FenPosition.startingPosition);

  Board.fromFEN(String fen) {
    FenPosition fenPosition = FenPosition.parse(fen);

    position = fenPosition.position;
    whiteToPlay = fenPosition.whiteToMove;
    enPassantSquare = fenPosition.enPassantSquare;
    whiteCastleKingSide = fenPosition.whiteCastleKingSide;
    whiteCastleQueenSide = fenPosition.whiteCastleQueenSide;
    blackCastleKingSide = fenPosition.blackCastleKingSide;
    blackCastleQueenSide = fenPosition.blackCastleQueenSide;

    zobristKey = Zobrist.getZobristForBoard(this);
    gameStateHistory = [];
    fiftyMoveRule = fenPosition.halfmoveClock;
    plyCount = (fenPosition.fullmoveNumber - 1) * 2 + (whiteToPlay ? 0 : 1);

    addMoveToHashHistory(zobristKey);
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
    int selectedPiece = position[move.startingSquare];
    int capturedPiece = position[move.targetSquare];
    int color = whiteToPlay ? Piece.white : Piece.black;

    gameState.enPassantSquare = enPassantSquare;
    gameState.capturedPiece = capturedPiece;
    int startingCastlingIndex = castlingRightsAsInt();

    // Remove selected piece from start square zobrist
    zobristKey ^= Zobrist.piecesArray[selectedPiece][move.startingSquare]; // Remove starting peice from starting square

    // Handle En passant file
    zobristKey ^= Zobrist.enPassantSquares[enPassantSquare + 1]; // Remove old enpassant square
    if (move.pawnTwoForward) {
      int direction = whiteToPlay ? -8 : 8;
      enPassantSquare = move.targetSquare - direction;
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
      int enPassantCaptureSquare = move.targetSquare + direction;

      zobristKey ^= Zobrist.piecesArray[position[enPassantCaptureSquare]]
          [enPassantCaptureSquare]; // Remove en passant capture square from zobrist
      gameState.capturedPiece = position[enPassantCaptureSquare];
      position[enPassantCaptureSquare] = 0;
    }

    // Castling
    if (move.castling) {
      int castlingRank = whiteToPlay ? 7 : 0;
      int rookStartingIndex = move.targetSquare % 8 == 2 ? castlingRank * 8 + 0 : castlingRank * 8 + 7;
      int rookTargetIndex = move.targetSquare % 8 == 2 ? castlingRank * 8 + 3 : castlingRank * 8 + 5;

      position[rookTargetIndex] = position[rookStartingIndex];
      position[rookStartingIndex] = 0;
      zobristKey ^= Zobrist.piecesArray[position[rookTargetIndex]][rookStartingIndex];
      zobristKey ^= Zobrist.piecesArray[position[rookTargetIndex]][rookTargetIndex];

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
        if (move.startingSquare == 56) {
          whiteCastleQueenSide = false;
        } else if (move.startingSquare == 63) {
          whiteCastleKingSide = false;
        }
      } else {
        if (move.startingSquare == 0) {
          blackCastleQueenSide = false;
        } else if (move.startingSquare == 7) {
          blackCastleKingSide = false;
        }
      }
    }
    if (Piece.type(capturedPiece) == Piece.rook) {
      if (Piece.isColor(capturedPiece, Piece.white)) {
        if (move.targetSquare == 56) {
          whiteCastleQueenSide = false;
        } else if (move.targetSquare == 63) {
          whiteCastleKingSide = false;
        }
      } else {
        if (move.targetSquare == 0) {
          blackCastleQueenSide = false;
        } else if (move.targetSquare == 7) {
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
    position[move.targetSquare] = selectedPiece;
    position[move.startingSquare] = 0;

    zobristKey ^= Zobrist.piecesArray[capturedPiece][move.targetSquare]; // Remove piece from target square
    zobristKey ^= Zobrist.piecesArray[selectedPiece][move.targetSquare]; // Add starting piece to target square

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
    int selectedPiece = position[move.targetSquare]; // The piece at the end square of the move we are undo
    int color = whiteToPlay ? Piece.black : Piece.white; // The last move was the opposite of the current state
    int capturedPiece = gameStateHistory.last.capturedPiece;

    // Handle promotion
    if (move.promotion != 0) {
      selectedPiece = Piece.pawn | color;
    }

    // Handle castles
    if (move.castling) {
      int castlingRank = whiteToPlay ? 0 : 7; // other way round
      int rookStartingIndex = move.targetSquare % 8 == 2 ? castlingRank * 8 + 0 : castlingRank * 8 + 7;
      int rookTargetIndex = move.targetSquare % 8 == 2 ? castlingRank * 8 + 3 : castlingRank * 8 + 5;

      position[rookStartingIndex] = position[rookTargetIndex];
      position[rookTargetIndex] = 0;

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
        if (move.startingSquare == 56) {
          whiteCastleQueenSide = gameStateHistory.last.whiteCastleQueenSide;
        } else if (move.startingSquare == 63) {
          whiteCastleKingSide = gameStateHistory.last.whiteCastleKingSide;
        }
      } else {
        if (move.startingSquare == 0) {
          blackCastleQueenSide = gameStateHistory.last.blackCastleQueenSide;
        } else if (move.startingSquare == 7) {
          blackCastleKingSide = gameStateHistory.last.blackCastleKingSide;
        }
      }
    }
    if (Piece.type(capturedPiece) == Piece.rook) {
      if (Piece.isColor(capturedPiece, Piece.white)) {
        if (move.targetSquare == 56) {
          whiteCastleQueenSide = gameStateHistory.last.whiteCastleQueenSide;
        } else if (move.targetSquare == 63) {
          whiteCastleKingSide = gameStateHistory.last.whiteCastleKingSide;
        }
      } else {
        if (move.targetSquare == 0) {
          blackCastleQueenSide = gameStateHistory.last.blackCastleQueenSide;
        } else if (move.targetSquare == 7) {
          blackCastleKingSide = gameStateHistory.last.blackCastleKingSide;
        }
      }
    }

    // Handle en passant captures
    if (move.enPassantCapture) {
      int direction = whiteToPlay ? -8 : 8; // The last move was the opposite of the current state
      int enPassantCaptureSquare = move.targetSquare + direction;

      position[enPassantCaptureSquare] = capturedPiece;
      capturedPiece = 0;
      enPassantSquare = move.targetSquare;
    }

    enPassantSquare = gameStateHistory.last.enPassantSquare;

    fiftyMoveRule = gameStateHistory.last.fiftyMoveRule;

    removeMoveFromHashHistory();
    zobristKey = gameStateHistory.last.zobristKey;
    gameStateHistory.removeLast();

    position[move.startingSquare] = selectedPiece;
    position[move.targetSquare] = capturedPiece;
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
}
