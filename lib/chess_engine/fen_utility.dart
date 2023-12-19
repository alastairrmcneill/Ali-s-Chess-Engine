import 'package:ace/chess_engine/loaded_position.dart';
import 'package:ace/chess_engine/piece.dart';
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
  FENUtility() {}

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
}
