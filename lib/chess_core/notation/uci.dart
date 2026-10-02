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

  static final RegExp _format = RegExp(r'^[a-h][1-8][a-h][1-8][qrbnQRBN]?$');

  factory UciMove.parse(String uci) {
    if (!_format.hasMatch(uci)) {
      if (uci.length == 5 && !"qrbn".contains(uci[4].toLowerCase())) {
        throw FormatException("Invalid promotion piece", uci);
      }
      throw FormatException("Invalid UCI move", uci);
    }
    String? promotion = uci.length == 5 ? uci[4].toLowerCase() : null;
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
