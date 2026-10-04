import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/notation/san.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:ace/chess_core/rules/zobrist.dart';

class Referee {
  final String startFen;
  final int maxPlies;
  late Board _board;
  late int _fullMoveNumber;
  final MoveGenerator _moveGenerator = MoveGenerator();
  List<Move>? _legalCache;
  final Map<String, int> _repetitions = {};
  final List<String> _uciHistory = [];
  final List<String> _sanHistory = [];
  static final RegExp _uciFormat = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

  static final String standardStartFen = FenPosition.startingPosition;

  static bool _zobristReady = false;

  Referee(this.startFen, {this.maxPlies = 600}) {
    if (!_zobristReady) {
      Zobrist();
      _zobristReady = true;
    }
    _board = Board.fromFEN(startFen);
    _fullMoveNumber = FenPosition.parse(startFen).fullmoveNumber;
    _countRepetition();
  }

  List<Move> _legal() => _legalCache ??= _moveGenerator.generateLegalMoves(_board);
  List<String> get uciHistory => _uciHistory;
  List<String> get sanHistory => _sanHistory;
  bool get whiteToMove => _board.whiteToPlay;
  int get pliesPlayed => _uciHistory.length;

  /// The full 6-field FEN of the current position.
  String get fen => FenPosition(
        position: _board.position,
        whiteCastleKingSide: _board.whiteCastleKingSide,
        whiteCastleQueenSide: _board.whiteCastleQueenSide,
        blackCastleKingSide: _board.blackCastleKingSide,
        blackCastleQueenSide: _board.blackCastleQueenSide,
        whiteToMove: _board.whiteToPlay,
        enPassantSquare: _board.enPassantSquare,
        halfmoveClock: _board.fiftyMoveRule,
        fullmoveNumber: _fullMoveNumber,
      ).toFen();

  void _countRepetition() {
    final key = _repetitionKey();
    _repetitions[key] = (_repetitions[key] ?? 0) + 1;
  }

  /// Pieces, side to move, castling rights and en passant. The en passant square only counts when
  /// an en passant capture is actually legal, as in the FIDE rules.
  String _repetitionKey() {
    final enPassantPossible = _legal().any((m) => m.enPassantCapture);
    return [
      _board.position.join(','),
      _board.whiteToPlay ? 'w' : 'b',
      _board.whiteCastleKingSide,
      _board.whiteCastleQueenSide,
      _board.blackCastleKingSide,
      _board.blackCastleQueenSide,
      enPassantPossible ? _board.enPassantSquare : -1,
    ].join('|');
  }

  bool _insufficientMaterial() {
    // Check insufficient material
    int numQueens = 0;
    int numRooks = 0;
    int numBishops = 0;
    List<int> whiteBishops = [];
    List<int> blackBishops = [];
    int numKnights = 0;
    int numPawns = 0;

    for (int i = 0; i < _board.position.length; i++) {
      int piece = _board.position[i];

      int pieceType = Piece.type(piece);
      switch (pieceType) {
        case Piece.queen:
          numQueens++;
          break;
        case Piece.rook:
          numRooks++;
          break;
        case Piece.bishop:
          numBishops++;
          Piece.isColor(piece, Piece.white) ? whiteBishops.add(i) : blackBishops.add(i);
          break;
        case Piece.knight:
          numKnights++;
          break;
        case Piece.pawn:
          numPawns++;
          break;
        default:
          break;
      }
    }

    if (numPawns + numRooks + numQueens + numKnights + numBishops == 0) {
      return true;
    } else if (numPawns + numRooks + numQueens == 0) {
      if ((numKnights == 1 && numBishops == 0) || (numBishops == 1 && numKnights == 0)) {
        return true;
      }

      if (numKnights == 0 && whiteBishops.length == 1 && blackBishops.length == 1) {
        // Check if the bishops are on the same squares
        int whiteBishopRank = whiteBishops[0] % 8;
        int whiteBishopFile = whiteBishops[0] ~/ 8;
        int blackBishopRank = blackBishops[0] % 8;
        int blackBishopFile = blackBishops[0] ~/ 8;
        int whiteSquareColor = (whiteBishopFile + whiteBishopRank) % 2;
        int blackSquareColor = (blackBishopFile + blackBishopRank) % 2;

        if (whiteSquareColor == blackSquareColor) {
          return true;
        }
      }
    }
    return false;
  }

  static String? _promotionLetter(Move move) => move.promotion == 0 ? null : ' qnrb'[move.promotion];

  static String _toUci(Move move) =>
      UciMove(from: move.startingSquare, to: move.targetSquare, promotion: _promotionLetter(move)).toString();

  String? tryPlayUci(String uci) {
    if (!_uciFormat.hasMatch(uci)) return "Malformed UCI move: $uci";

    final UciMove parsed = UciMove.parse(uci);

    for (final move in _legal()) {
      if (move.startingSquare == parsed.from &&
          move.targetSquare == parsed.to &&
          _promotionLetter(move) == parsed.promotion) {
        _apply(move);
        return null;
      }
    }
    return "Illegal UCI move $uci";
  }

  String? tryPlaySan(String san) {
    final move = San.toLegalMove(_board, san, _legal());

    if (move == null) return "Illegal SAN move $san";
    _apply(move);
    return null;
  }

  void _apply(Move move) {
    final uci = _toUci(move);
    final san = San.fromMove(_board, move, _legal());
    final wasBlack = !_board.whiteToPlay;
    _board.makeMove(move);
    if (wasBlack) _fullMoveNumber++;
    _legalCache = null;
    _uciHistory.add(uci);
    _sanHistory.add(san);
    _countRepetition();
  }

  GameEnd? checkGameEnd() {
    final legalMoves = _legal();

    if (legalMoves.isEmpty) {
      if (_moveGenerator.inCheck) {
        return GameEnd(
          outcome: whiteToMove ? GameOutcome.blackWin : GameOutcome.whiteWin,
          termination: GameTermination.checkmate,
        );
      }
      return const GameEnd(
        outcome: GameOutcome.draw,
        termination: GameTermination.stalemate,
      );
    }

    if (_insufficientMaterial()) {
      return const GameEnd(
        outcome: GameOutcome.draw,
        termination: GameTermination.insufficientMaterial,
      );
    }
    if ((_repetitions[_repetitionKey()] ?? 0) >= 3) {
      return const GameEnd(outcome: GameOutcome.draw, termination: GameTermination.threefoldRepetition);
    }
    if (_board.fiftyMoveRule >= 100) {
      return const GameEnd(outcome: GameOutcome.draw, termination: GameTermination.fiftyMoveRule);
    }
    if (pliesPlayed >= maxPlies) {
      return const GameEnd(outcome: GameOutcome.draw, termination: GameTermination.maxMoves);
    }
    return null;
  }
}
