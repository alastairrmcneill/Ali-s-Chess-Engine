import 'package:ace/chess_engine/core/board.dart';
import 'package:ace/chess_engine/helpers/loaded_position.dart';
import 'package:ace/chess_engine/core/piece.dart';
import 'package:ace/extensions/string_extension.dart';

class FENUtility {
  static String startingPosition = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
  static Map<String, int> pieceSymbols = {
    "p": Piece.pawn,
    "n": Piece.knight,
    "b": Piece.bishop,
    "r": Piece.rook,
    "q": Piece.queen,
    "k": Piece.king,
  };

  static LoadedPositionInfo loadPositionFromFEN(String fen) {
    LoadedPositionInfo loadedPositionInfo = LoadedPositionInfo();
    List<String> sections = fen.split(" ");

    // Look at the pieces
    int index = 0;
    for (var i = 0; i < sections[0].length; i++) {
      String char = sections[0][i];

      if (char != "/") {
        if (char.isNumeric()) {
          index += int.parse(char);
        } else {
          int pieceColor = char.isUpperCase() ? Piece.white : Piece.black;

          int pieceType = pieceSymbols[char.toLowerCase()]!;

          loadedPositionInfo.position[index] = pieceColor | pieceType;
          index += 1;
        }
      }
    }

    // Move
    loadedPositionInfo.whiteToMove = sections[1] == "w";

    // Castling
    loadedPositionInfo.whiteCastleKingSide = sections[2].contains("K");
    loadedPositionInfo.whiteCastleQueenSide = sections[2].contains("Q");
    loadedPositionInfo.blackCastleKingSide = sections[2].contains("k");
    loadedPositionInfo.blackCastleQueenSide = sections[2].contains("q");

    // En passant square
    // loadedPositionInfo.enPassantSquare = int.parse(sections[3]);

    // Ply count
    loadedPositionInfo.plyCount = int.parse(sections[4]);

    return loadedPositionInfo;
  }

  static String fenFromBoard(Board board) {
    String fen = "";
    for (int rank = 0; rank < 8; rank++) {
      int numEmptyFiles = 0;
      for (int file = 0; file < 8; file++) {
        int i = rank * 8 + file;
        int piece = board.position[i];
        if (piece != 0) {
          if (numEmptyFiles != 0) {
            fen += numEmptyFiles.toString();
            numEmptyFiles = 0;
          }
          bool isBlack = Piece.isColor(piece, Piece.black);
          int pieceType = Piece.type(piece);
          String pieceChar = ' ';
          switch (pieceType) {
            case Piece.rook:
              pieceChar = 'R';
              break;
            case Piece.knight:
              pieceChar = 'N';
              break;
            case Piece.bishop:
              pieceChar = 'B';
              break;
            case Piece.queen:
              pieceChar = 'Q';
              break;
            case Piece.king:
              pieceChar = 'K';
              break;
            case Piece.pawn:
              pieceChar = 'P';
              break;
          }
          fen += (isBlack) ? pieceChar.toLowerCase() : pieceChar.toUpperCase();
        } else {
          numEmptyFiles++;
        }
      }
      if (numEmptyFiles != 0) {
        fen += numEmptyFiles.toString();
      }
      if (rank != 7) {
        fen += '/';
      }
    }

    // Check turn
    fen += board.whiteToPlay ? " w" : " b";

    // Castling
    fen += ' ';
    fen += (board.whiteCastleKingSide) ? "K" : "";
    fen += (board.whiteCastleQueenSide) ? "Q" : "";
    fen += (board.blackCastleKingSide) ? "k" : "";
    fen += (board.blackCastleQueenSide) ? "q" : "";
    fen += (!board.whiteCastleKingSide &&
            !board.whiteCastleQueenSide &&
            !board.blackCastleKingSide &&
            !board.blackCastleQueenSide)
        ? "-"
        : "";

    // En-passant
    fen += ' ';
    int enPassantFile = board.enPassantSquare % 8;
    int enPassantRank = board.enPassantSquare ~/ 8;

    String files = "abcdefgh";

    if (board.enPassantSquare == -1) {
      fen += '-';
    } else {
      fen += "${files[enPassantFile]}$enPassantRank";
    }

    return fen;
  }
}
