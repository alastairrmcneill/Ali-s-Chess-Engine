import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/board_helper.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/move_generator.dart';

/// A move in UCI long algebraic notation (e.g. "e2e4", "e7e8q"), independent of any engine's move type.
///
/// Square indexes use the same convention as the boards: 0 = a8, 63 = h1.
class UciMove {
  static const String promotionLetters = " qnrb"; // Index matches Move.promotion (1 = queen ... 4 = bishop)

  final int from;
  final int to;
  final String? promotion; // 'q', 'r', 'b', 'n' or null

  UciMove(this.from, this.to, [this.promotion]);

  factory UciMove.parse(String uci) {
    if (uci.length != 4 && uci.length != 5) throw FormatException("Invalid UCI move", uci);
    String? promotion = uci.length == 5 ? uci[4].toLowerCase() : null;
    if (promotion != null && !"qrbn".contains(promotion)) throw FormatException("Invalid promotion piece", uci);
    return UciMove(BoardHelper.squareIndex(uci.substring(0, 2)), BoardHelper.squareIndex(uci.substring(2, 4)), promotion);
  }

  /// The Move.promotion code for this move (0 when it isn't a promotion)
  int get promotionCode => promotion == null ? 0 : promotionLetters.indexOf(promotion!);

  @override
  String toString() => "${BoardHelper.squareName(from)}${BoardHelper.squareName(to)}${promotion ?? ""}";
}

class Uci {
  static String fromMove(Move move) => move.toChessNotation();

  /// Finds the legal move matching [uci] in the current position, or null if it isn't legal (or can't be parsed).
  static Move? toLegalMove(Board board, String uci, [MoveGenerator? moveGenerator]) {
    UciMove parsed;
    try {
      parsed = UciMove.parse(uci);
    } on FormatException {
      return null;
    }

    for (Move move in (moveGenerator ?? MoveGenerator()).generateLegalMoves(board)) {
      if (move.startingSquare == parsed.from &&
          move.targetSquare == parsed.to &&
          move.promotion == parsed.promotionCode) {
        return move;
      }
    }
    return null;
  }
}
