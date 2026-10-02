import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';

class San {
  static const String _pieceLetters = "  PNBRQ"; // Indexed by piece type, king handled separately

  static String fromMove(Board board, Move move, List<Move> legalMoves, {bool includeCheckIndicators = true}) {
    String san = _withoutCheckIndicators(board, move, legalMoves);

    // Check or checkmate suffix
    board.makeMove(move);
    MoveGenerator moveGenerator = MoveGenerator();
    bool noMoves = moveGenerator.generateLegalMoves(board).isEmpty;
    if (moveGenerator.inCheck) san += noMoves ? "#" : "+";
    board.unMakeMove(move);

    return san;
  }

  /// Finds the legal move written as [san] in the current position, or null if there isn't one.
  static Move? toLegalMove(Board board, String san, List<Move> legalMoves) {
    String wanted = _normalise(san);
    for (Move move in legalMoves) {
      if (_normalise(_withoutCheckIndicators(board, move, legalMoves)) == wanted) return move;
    }
    return null;
  }

  static String _normalise(String san) {
    return san.replaceAll(RegExp(r"[+#!?]"), "").replaceAll("0", "O").replaceAll("=", "");
  }

  static String _withoutCheckIndicators(Board board, Move move, List<Move> legalMoves) {
    if (move.castling) {
      return BoardHelper.getFileFromIndex(move.targetSquare) == 6 ? 'O-O' : 'O-O-O';
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
