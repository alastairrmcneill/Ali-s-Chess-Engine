import 'package:ace/chess_engine/fen_utility.dart';
import 'package:ace/chess_engine/loaded_position.dart';

class Board {
  late List<int> position;
  late bool whiteToPlay;

  Board() {
    position = List.generate(64, (index) => index);
    // loadFromStartingPosition();
    loadFromCustomPosition();
  }

  loadFromStartingPosition() {
    LoadedPositionInfo loadedPositionInfo = FENUtility.loadPositionFromFEN(FENUtility.startingPosition);
    position = loadedPositionInfo.position;
    whiteToPlay = loadedPositionInfo.whiteToMove;
  }

  loadFromCustomPosition() {
    LoadedPositionInfo loadedPositionInfo =
        FENUtility.loadPositionFromFEN("rnbqkbnr/8/8/8/8/8/8/RNBQKBNR w KQkq - 0 1");
    position = loadedPositionInfo.position;
    whiteToPlay = loadedPositionInfo.whiteToMove;
  }
}
