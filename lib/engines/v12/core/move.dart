import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/v12/core/piece.dart';

// Move is packed into an int
// From: 0-5 bits,
// To: 6-11 bits,
// Flags 12-15 bits

extension type const Move.raw(int value) {
  static const _noFlag = 0;
  static const _enPassantCapture = 1;
  static const _castling = 2;
  static const _pawnTwoForward = 3;
  static const _promoteToQueen = 4;

  static const Move invalid = Move.raw(0);

  Move.encode(int from, int to, [int flag = 0]) : value = from | (to << 6) | (flag << 12);

  Move({
    required int startingSquare,
    required int targetSquare,
    bool enPassantCapture = false,
    bool pawnTwoForward = false,
    int promotion = 0,
    bool castling = false,
  }) : value = startingSquare |
            (targetSquare << 6) |
            ((promotion != 0
                    ? (promotion + 3)
                    : enPassantCapture
                        ? _enPassantCapture
                        : castling
                            ? _castling
                            : pawnTwoForward
                                ? _pawnTwoForward
                                : _noFlag) <<
                12);

  int get from => value & 0x3F;
  int get to => (value >>> 6) & 0x3F;
  int get flag => value >>> 12;
  bool get enPassantCapture => flag == _enPassantCapture;
  bool get pawnTwoForward => flag == _pawnTwoForward;
  bool get castling => flag == _castling;
  int get promotion => isPromotion ? flag - 3 : 0;
  bool get isPromotion => flag >= _promoteToQueen;
  bool get isNoMove => value == 0;

  String get uci => UciMove(
        from: from,
        to: to,
        promotion: promotion == 0 ? null : " qnrb"[promotion],
      ).toString();

  int promotingPiece() {
    switch (promotion) {
      case 1:
        return Piece.queen;
      case 2:
        return Piece.knight;
      case 3:
        return Piece.rook;
      case 4:
        return Piece.bishop;
      default:
        return Piece.none;
    }
  }

  String toChessNotation() {
    String files = "abcdefgh";

    int startingFile = BoardHelper.getFileFromIndex(from);
    int startingRank = 8 - BoardHelper.getRankFromIndex(from);
    int targetFile = BoardHelper.getFileFromIndex(to);
    int targetRank = 8 - BoardHelper.getRankFromIndex(to);

    return "${files[startingFile]}$startingRank${files[targetFile]}$targetRank";
  }
}
