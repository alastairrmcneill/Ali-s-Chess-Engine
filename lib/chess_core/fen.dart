import 'package:ace/chess_core/board_helper.dart';

/// A position parsed from a FEN string, independent of any engine's board representation.
///
/// Squares use FEN order: index 0 = a8, 7 = h8, 56 = a1, 63 = h1.
/// Each square holds a FEN piece letter ('P', 'n', 'K', ...) or null when empty.
/// Every engine version maps this into its own board, so FEN parsing only lives here.
class FenPosition {
  static const String startingFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
  static const String _pieceLetters = "pnbrqkPNBRQK";

  final List<String?> squares;
  final bool whiteToMove;
  final bool whiteCastleKingSide;
  final bool whiteCastleQueenSide;
  final bool blackCastleKingSide;
  final bool blackCastleQueenSide;
  final int enPassantSquare; // -1 if there is no en passant square
  final int halfmoveClock; // Plies since the last capture or pawn move (50 move rule)
  final int fullmoveNumber;

  FenPosition({
    required this.squares,
    required this.whiteToMove,
    required this.whiteCastleKingSide,
    required this.whiteCastleQueenSide,
    required this.blackCastleKingSide,
    required this.blackCastleQueenSide,
    required this.enPassantSquare,
    required this.halfmoveClock,
    required this.fullmoveNumber,
  });

  /// Parses a FEN. EPD style strings without the two clock fields are accepted too.
  factory FenPosition.parse(String fen) {
    List<String> sections = fen.trim().split(RegExp(r"\s+"));
    if (sections.length < 4) throw FormatException("FEN needs at least 4 fields", fen);

    // Pieces
    List<String?> squares = List.filled(64, null);
    List<String> ranks = sections[0].split("/");
    if (ranks.length != 8) throw FormatException("FEN needs 8 ranks", fen);
    for (int rank = 0; rank < 8; rank++) {
      int file = 0;
      for (String char in ranks[rank].split("")) {
        int? emptySquares = int.tryParse(char);
        if (emptySquares != null) {
          file += emptySquares;
        } else if (_pieceLetters.contains(char)) {
          if (file > 7) throw FormatException("Too many squares in rank ${8 - rank}", fen);
          squares[rank * 8 + file] = char;
          file++;
        } else {
          throw FormatException("Unknown piece '$char'", fen);
        }
      }
      if (file != 8) throw FormatException("Rank ${8 - rank} does not have 8 squares", fen);
    }

    // Side to move
    if (sections[1] != "w" && sections[1] != "b") throw FormatException("Side to move must be w or b", fen);

    // En passant
    int enPassantSquare = sections[3] == "-" ? -1 : BoardHelper.squareIndex(sections[3]);

    return FenPosition(
      squares: squares,
      whiteToMove: sections[1] == "w",
      whiteCastleKingSide: sections[2].contains("K"),
      whiteCastleQueenSide: sections[2].contains("Q"),
      blackCastleKingSide: sections[2].contains("k"),
      blackCastleQueenSide: sections[2].contains("q"),
      enPassantSquare: enPassantSquare,
      halfmoveClock: sections.length > 4 ? int.parse(sections[4]) : 0,
      fullmoveNumber: sections.length > 5 ? int.parse(sections[5]) : 1,
    );
  }

  String toFen() {
    String fen = "";
    for (int rank = 0; rank < 8; rank++) {
      int numEmptyFiles = 0;
      for (int file = 0; file < 8; file++) {
        String? piece = squares[rank * 8 + file];
        if (piece == null) {
          numEmptyFiles++;
          continue;
        }
        if (numEmptyFiles != 0) {
          fen += numEmptyFiles.toString();
          numEmptyFiles = 0;
        }
        fen += piece;
      }
      if (numEmptyFiles != 0) fen += numEmptyFiles.toString();
      if (rank != 7) fen += "/";
    }

    String castling = "${whiteCastleKingSide ? "K" : ""}${whiteCastleQueenSide ? "Q" : ""}"
        "${blackCastleKingSide ? "k" : ""}${blackCastleQueenSide ? "q" : ""}";
    String enPassant = enPassantSquare == -1 ? "-" : BoardHelper.squareName(enPassantSquare);

    return "$fen ${whiteToMove ? "w" : "b"} ${castling.isEmpty ? "-" : castling} $enPassant "
        "$halfmoveClock $fullmoveNumber";
  }
}
