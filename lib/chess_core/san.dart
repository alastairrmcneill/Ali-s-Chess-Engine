import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';

/// Standard Algebraic Notation (Nf3, exd5, O-O, e8=Q+) for the rules board.
class San {
  static const String _pieceLetters = ' KPNBRQ'; // indexed by Piece type; pawns get no letter
  static const String _promotionLetters = 'QNRB'; // rules Move promotion codes 1..4

  /// SAN for [move], which must be legal in [board]'s current position.
  /// [legal] is every legal move in this position (needed for disambiguation).
  /// Set [withCheck] to false to skip the +/# suffix (faster; used when parsing).
  static String fromMove(Board board, Move move, List<Move> legal, {bool withCheck = true}) {
    final san = _withoutCheck(board, move, legal);
    return withCheck ? san + _checkSuffix(board, move) : san;
  }

  /// The legal move matching a SAN token, or null if none matches (illegal or ambiguous).
  static Move? parse(Board board, String token, List<Move> legal) {
    final normalised = _normalise(token);
    for (final move in legal) {
      if (_withoutCheck(board, move, legal) == normalised) return move;
    }
    return null;
  }

  static String _withoutCheck(Board board, Move move, List<Move> legal) {
    if (move.castling) {
      return BoardHelper.getFileFromIndex(move.targetSquare) == 6 ? 'O-O' : 'O-O-O';
    }

    final pieceType = Piece.type(board.position[move.startingSquare]);
    final isCapture = board.position[move.targetSquare] != Piece.none || move.enPassantCapture;
    final target = BoardHelper.squareName(move.targetSquare);

    if (pieceType == Piece.pawn) {
      var san = '';
      if (isCapture) san += '${BoardHelper.files[BoardHelper.getFileFromIndex(move.startingSquare)]}x';
      san += target;
      if (move.promotion != 0) san += '=${_promotionLetters[move.promotion - 1]}';
      return san;
    }

    return _pieceLetters[pieceType] + _disambiguation(board, move, legal, pieceType) + (isCapture ? 'x' : '') + target;
  }

  static String _disambiguation(Board board, Move move, List<Move> legal, int pieceType) {
    final others = legal.where((m) =>
        m.targetSquare == move.targetSquare &&
        m.startingSquare != move.startingSquare &&
        Piece.type(board.position[m.startingSquare]) == pieceType);
    if (others.isEmpty) return '';

    final file = BoardHelper.getFileFromIndex(move.startingSquare);
    final rank = BoardHelper.getRankFromIndex(move.startingSquare);
    final fileName = BoardHelper.files[file];
    final rankName = '${8 - rank}';

    if (others.every((m) => BoardHelper.getFileFromIndex(m.startingSquare) != file)) return fileName;
    if (others.every((m) => BoardHelper.getRankFromIndex(m.startingSquare) != rank)) return rankName;
    return fileName + rankName;
  }

  static String _checkSuffix(Board board, Move move) {
    // A separate generator: generateLegalMoves overwrites the generator's internal state (inCheck etc.).
    final generator = MoveGenerator();
    board.makeMove(move);
    final replies = generator.generateLegalMoves(board);
    final inCheck = generator.inCheck;
    board.unMakeMove(move);
    if (!inCheck) return '';
    return replies.isEmpty ? '#' : '+';
  }

  static String _normalise(String token) {
    var san = token.trim().replaceAll(RegExp(r'[+#!?]+$'), '');
    if (san == '0-0-0') san = 'O-O-O';
    if (san == '0-0') san = 'O-O';
    // Accept promotions written without '=' (e8Q → e8=Q).
    final promotion = RegExp(r'^([a-h](?:x[a-h])?[18])([QRBN])$').firstMatch(san);
    if (promotion != null) san = '${promotion.group(1)}=${promotion.group(2)}';
    return san;
  }
}
