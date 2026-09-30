import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/move_generator.dart';
import 'package:ace/chess_core/piece.dart';

enum Result {
  playing,
  whiteIsMated,
  blackIsMated,
  stalemate,
  repetition,
  fiftyMoveRule,
  insufficientMaterial,
}

extension ResultInfo on Result {
  bool get isDraw =>
      this == Result.stalemate ||
      this == Result.repetition ||
      this == Result.fiftyMoveRule ||
      this == Result.insufficientMaterial;

  /// PGN result string
  String get pgn => switch (this) {
        Result.playing => "*",
        Result.whiteIsMated => "0-1",
        Result.blackIsMated => "1-0",
        _ => "1/2-1/2",
      };
}

class GameResult {
  /// Checks all possible end of game conditions for the current position
  static Result check(Board board, [MoveGenerator? moveGenerator]) {
    moveGenerator ??= MoveGenerator();

    // Check if stalemate or checkmate
    if (moveGenerator.generateLegalMoves(board).isEmpty) {
      if (moveGenerator.inCheck) {
        return board.whiteToPlay ? Result.whiteIsMated : Result.blackIsMated;
      }
      return Result.stalemate;
    }

    // Check 50 moves
    if (board.fiftyMoveRule >= 100) return Result.fiftyMoveRule;

    // Check 3 fold repetition of the current position
    if (board.repetitionCount >= 3) return Result.repetition;

    if (isInsufficientMaterial(board)) return Result.insufficientMaterial;

    // If all pass then we are still playing
    return Result.playing;
  }

  static bool isInsufficientMaterial(Board board) {
    int numQueens = 0;
    int numRooks = 0;
    int numKnights = 0;
    int numPawns = 0;
    List<int> whiteBishops = [];
    List<int> blackBishops = [];

    for (int i = 0; i < board.position.length; i++) {
      int piece = board.position[i];

      switch (Piece.type(piece)) {
        case Piece.queen:
          numQueens++;
        case Piece.rook:
          numRooks++;
        case Piece.bishop:
          Piece.isColor(piece, Piece.white) ? whiteBishops.add(i) : blackBishops.add(i);
        case Piece.knight:
          numKnights++;
        case Piece.pawn:
          numPawns++;
        default:
          break;
      }
    }

    int numBishops = whiteBishops.length + blackBishops.length;
    if (numPawns + numRooks + numQueens > 0) return false;

    // King vs king, or king and a single minor piece vs king
    if (numKnights + numBishops <= 1) return true;

    // King and bishop vs king and bishop with both bishops on the same colour squares
    if (numKnights == 0 && whiteBishops.length == 1 && blackBishops.length == 1) {
      int whiteSquareColor = (whiteBishops[0] ~/ 8 + whiteBishops[0] % 8) % 2;
      int blackSquareColor = (blackBishops[0] ~/ 8 + blackBishops[0] % 8) % 2;
      return whiteSquareColor == blackSquareColor;
    }

    return false;
  }
}
