import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/board_helper.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/move_generator.dart';
import 'package:ace/chess_core/piece.dart';

/// Standard Algebraic Notation (e.g. "Nf3", "exd6", "O-O", "e8=Q+"), as used in PGN files.
class San {
  static const String _pieceLetters = "  PNBRQ"; // Indexed by piece type, king handled separately

  /// SAN for [move], which must be legal in the current position of [board].
  static String fromMove(Board board, Move move) {
    String san = _withoutCheck(board, move, MoveGenerator().generateLegalMoves(board));

    // Check or checkmate suffix
    board.makeMove(move);
    MoveGenerator moveGenerator = MoveGenerator();
    bool noMoves = moveGenerator.generateLegalMoves(board).isEmpty;
    if (moveGenerator.inCheck) san += noMoves ? "#" : "+";
    board.unMakeMove(move);

    return san;
  }

  /// Finds the legal move written as [san] in the current position, or null if there isn't one.
  static Move? toLegalMove(Board board, String san) {
    String wanted = _normalise(san);
    List<Move> legalMoves = MoveGenerator().generateLegalMoves(board);
    for (Move move in legalMoves) {
      if (_normalise(_withoutCheck(board, move, legalMoves)) == wanted) return move;
    }
    return null;
  }

  static String _normalise(String san) {
    return san.replaceAll(RegExp(r"[+#!?]"), "").replaceAll("0", "O").replaceAll("=", "");
  }

  static String _withoutCheck(Board board, Move move, List<Move> legalMoves) {
    if (move.castling) {
      return BoardHelper.getFileFromIndex(move.targetSquare) == 6 ? "O-O" : "O-O-O";
    }

    int piece = board.position[move.startingSquare];
    int pieceType = Piece.type(piece);
    bool isCapture = board.position[move.targetSquare] != Piece.none || move.enPassantCapture;
    String target = BoardHelper.squareName(move.targetSquare);

    if (pieceType == Piece.pawn) {
      String from = BoardHelper.squareName(move.startingSquare);
      String promotion = move.promotion == 0 ? "" : "=${Piece.toFenChar(move.promotingPiece())}";
      return "${isCapture ? "${from[0]}x" : ""}$target$promotion";
    }

    String letter = pieceType == Piece.king ? "K" : _pieceLetters[pieceType];

    // Disambiguate when another piece of the same type can also reach the target square
    String disambiguation = "";
    List<Move> rivals = legalMoves
        .where((other) =>
            other.targetSquare == move.targetSquare &&
            other.startingSquare != move.startingSquare &&
            board.position[other.startingSquare] == piece)
        .toList();
    if (rivals.isNotEmpty) {
      int file = BoardHelper.getFileFromIndex(move.startingSquare);
      int rank = BoardHelper.getRankFromIndex(move.startingSquare);
      String from = BoardHelper.squareName(move.startingSquare);
      if (rivals.every((other) => BoardHelper.getFileFromIndex(other.startingSquare) != file)) {
        disambiguation = from[0];
      } else if (rivals.every((other) => BoardHelper.getRankFromIndex(other.startingSquare) != rank)) {
        disambiguation = from[1];
      } else {
        disambiguation = from;
      }
    }

    return "$letter$disambiguation${isCapture ? "x" : ""}$target";
  }
}
