import 'package:ace/chess_core/notation/piece.dart';

class FenPosition {
  static String startingPosition = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
  static final Map<String, int> _pieceSymbols = {
    "p": Piece.pawn,
    "n": Piece.knight,
    "b": Piece.bishop,
    "r": Piece.rook,
    "q": Piece.queen,
    "k": Piece.king,
  };

  final List<int> position;
  final bool whiteCastleKingSide;
  final bool whiteCastleQueenSide;
  final bool blackCastleKingSide;
  final bool blackCastleQueenSide;
  final bool whiteToMove;
  final int enPassantSquare;
  final int halfmoveClock;
  final int fullmoveNumber;

  FenPosition({
    required this.position,
    required this.whiteCastleKingSide,
    required this.whiteCastleQueenSide,
    required this.blackCastleKingSide,
    required this.blackCastleQueenSide,
    required this.whiteToMove,
    required this.enPassantSquare,
    required this.halfmoveClock,
    required this.fullmoveNumber,
  });

  factory FenPosition.parse(String fen) {
    List<int> position = List.filled(64, 0);
    int enPassantSquare = -1;

    List<String> sections = fen.split(" ");

    // Look at the pieces
    int index = 0;
    for (var i = 0; i < sections[0].length; i++) {
      String char = sections[0][i];

      if (char != "/") {
        if (_isDigit(char)) {
          index += int.parse(char);
        } else {
          int pieceColor = char == char.toUpperCase() ? Piece.white : Piece.black;

          int pieceType = _pieceSymbols[char.toLowerCase()]!;

          position[index] = pieceColor | pieceType;
          index += 1;
        }
      }
    }

    // Move
    final bool whiteToMove = sections[1] == "w";

    // Castling
    final bool whiteCastleKingSide = sections[2].contains("K");
    final bool whiteCastleQueenSide = sections[2].contains("Q");
    final bool blackCastleKingSide = sections[2].contains("k");
    final bool blackCastleQueenSide = sections[2].contains("q");

    // En passant square
    String files = "abcdefgh";
    if (sections[3] != "-") {
      //e.g. e6 = 20
      int file = files.indexOf(sections[3][0]);
      int rank = int.parse(sections[3][1]);
      enPassantSquare = (8 - rank) * 8 + file;
    }

    return FenPosition(
      position: position,
      whiteCastleKingSide: whiteCastleKingSide,
      whiteCastleQueenSide: whiteCastleQueenSide,
      blackCastleKingSide: blackCastleKingSide,
      blackCastleQueenSide: blackCastleQueenSide,
      whiteToMove: whiteToMove,
      enPassantSquare: enPassantSquare,
      halfmoveClock: sections.length > 4 ? int.parse(sections[4]) : 0,
      fullmoveNumber: sections.length > 5 ? int.parse(sections[5]) : 1,
    );
  }

  static bool _isDigit(String char) => '0123456789'.contains(char);
}
