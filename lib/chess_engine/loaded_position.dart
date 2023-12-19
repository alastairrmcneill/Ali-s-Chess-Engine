import 'package:ace/chess_engine/piece.dart';

class LoadedPositionInfo {
  late List<int> position;
  late bool whiteCastleKingSide;
  late bool whiteCastleQueenSide;
  late bool blackCastleKingSide;
  late bool blackCastleQueenSide;
  late int plyCount;
  late bool whiteToMove;
  late int enPassantSquare;

  LoadedPositionInfo() {
    position = List.filled(64, 0);
    whiteCastleKingSide = false;
    whiteCastleQueenSide = false;
    blackCastleKingSide = false;
    blackCastleQueenSide = false;
    plyCount = 0;
    whiteToMove = false;
    enPassantSquare = 0;
  }

  @override
  String toString() {
    String returnString = "Board: \n";
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 8; j++) {
        int piece = position[i * 8 + j];
        returnString += Piece.print(piece);
      }
      returnString += "\n";
    }
    returnString += "\n";

    returnString += "White to move: $whiteToMove";
    returnString += "\n";
    returnString += "White castle king side: $whiteCastleKingSide";
    returnString += "\n";
    returnString += "White castle queen side: $whiteCastleQueenSide";
    returnString += "\n";
    returnString += "Black castle king side: $blackCastleKingSide";
    returnString += "\n";
    returnString += "Black castle queen side: $blackCastleQueenSide";
    returnString += "\n";
    returnString += "En Passant Square: $enPassantSquare";
    returnString += "\n";
    returnString += "Ply count: $plyCount";
    returnString += "\n";

    return returnString;
  }
}
