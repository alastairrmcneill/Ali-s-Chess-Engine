import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/engines/v0/core/game_state.dart';
import 'package:ace/engines/v0/core/move.dart';
import 'package:ace/engines/v0/core/piece.dart';

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
  late int plyCount;

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

    gameStateHistory = [];
    fiftyMoveRule = fenPosition.halfmoveClock;
    plyCount = (fenPosition.fullmoveNumber - 1) * 2 + (whiteToPlay ? 0 : 1);
  }

  makeMove(Move move) {
    // Set up current game state
    GameState gameState = GameState();
    gameState.whiteCastleKingSide = whiteCastleKingSide;
    gameState.whiteCastleQueenSide = whiteCastleQueenSide;
    gameState.blackCastleKingSide = blackCastleKingSide;
    gameState.blackCastleQueenSide = blackCastleQueenSide;

    // Who is moving to where
    int selectedPiece = position[move.startingSquare];
    int capturedPiece = position[move.targetSquare];
    int color = whiteToPlay ? Piece.white : Piece.black;

    gameState.enPassantSquare = enPassantSquare;
    gameState.capturedPiece = capturedPiece;

    // Handle En passant file
    if (move.pawnTwoForward) {
      int direction = whiteToPlay ? -8 : 8;
      enPassantSquare = move.targetSquare - direction;
    } else {
      enPassantSquare = -1;
    }

    // Handle promotion
    if (move.promotion != 0) {
      selectedPiece = move.promotingPiece() | color;
    }

    // Handle en passant captures
    if (move.enPassantCapture) {
      int direction = whiteToPlay ? 8 : -8;
      int enPassantCaptureSquare = move.targetSquare + direction;

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

    // End of castling

    // Update positions
    position[move.targetSquare] = selectedPiece;
    position[move.startingSquare] = 0;

    // Swap sides
    whiteToPlay = !whiteToPlay;

    gameState.fiftyMoveRule = fiftyMoveRule;
    fiftyMoveRule++;
    if (Piece.type(selectedPiece) == Piece.pawn || Piece.type(capturedPiece) != Piece.none) {
      fiftyMoveRule = 0;
    }

    gameStateHistory.add(gameState);
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

    gameStateHistory.removeLast();

    position[move.startingSquare] = selectedPiece;
    position[move.targetSquare] = capturedPiece;
    whiteToPlay = !whiteToPlay;
  }

}
