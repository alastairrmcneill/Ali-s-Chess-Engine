import 'package:ace/chess_core/notation/board_helper.dart';

class UciMove {
  final int from;
  final int to;
  final String? promotion;

  UciMove({
    required this.from,
    required this.to,
    this.promotion,
  });

  factory UciMove.parse(String uci) {
    if (uci.length != 4 && uci.length != 5) throw FormatException("Invalid UCI move", uci);
    if (!"abcdefgh".contains(uci[0]) || !"12345678".contains(uci[1]) || !"abcdefgh".contains(uci[2]) || !"12345678".contains(uci[3])) {
      throw FormatException("Invalid square in UCI move", uci);
    }
    String? promotion = uci.length == 5 ? uci[4].toLowerCase() : null;
    if (promotion != null && !"qrbn".contains(promotion)) throw FormatException("Invalid promotion piece", uci);
    return UciMove(
      from: BoardHelper.squareIndex(uci.substring(0, 2)),
      to: BoardHelper.squareIndex(uci.substring(2, 4)),
      promotion: promotion,
    );
  }

  @override
  String toString() {
    return '${BoardHelper.squareName(from)}${BoardHelper.squareName(to)}${promotion ?? ''}';
  }
}
