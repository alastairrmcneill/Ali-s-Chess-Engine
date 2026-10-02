import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:ace/chess_core/rules/zobrist.dart';
import 'package:ace/chess_core/san.dart';

/// The neutral judge. Uses chess_core's own rules board, never an engine's.
class Referee {
  static final String standardStartFen = FenPosition.startingPosition;
  static final RegExp _uciFormat = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');
  static bool _zobristReady = false;

  final String startFen;

  /// Total plies after [startFen] before the game is drawn by [GameTermination.maxMoves].
  final int maxPlies;

  late final Board _board;
  final MoveGenerator _generator = MoveGenerator();
  List<Move>? _legalCache;
  final Map<String, int> _repetitions = {};
  final List<String> _uciHistory = [];
  final List<String> _sanHistory = [];

  Referee(this.startFen, {this.maxPlies = 600}) {
    if (!_zobristReady) {
      Zobrist(); // the rules board updates a hash on every move; the referee itself doesn't use it
      _zobristReady = true;
    }
    _board = Board.fromFEN(startFen);
    _countRepetition();
  }

  bool get whiteToMove => _board.whiteToPlay;
  int get pliesPlayed => _uciHistory.length;
  List<String> get uciHistory => List.unmodifiable(_uciHistory);
  List<String> get sanHistory => List.unmodifiable(_sanHistory);

  /// The piece code (chess_core/notation/piece.dart) on [index], a8 = 0 … h1 = 63.
  int pieceAt(int index) => _board.position[index];

  List<String> legalUciMoves() => _legal().map(_toUci).toList();

  /// Plays [uci] if legal. Returns null on success, otherwise the reason it was rejected.
  String? tryPlayUci(String uci) {
    if (!_uciFormat.hasMatch(uci)) return 'malformed UCI move "$uci"';
    final parsed = UciMove.parse(uci);
    for (final move in _legal()) {
      if (move.startingSquare == parsed.from && move.targetSquare == parsed.to && _promotionLetter(move) == parsed.promotion) {
        _apply(move);
        return null;
      }
    }
    return 'illegal move "$uci"';
  }

  /// Plays a SAN move (e.g. "Nf3") if legal. Returns null on success, otherwise the reason.
  String? tryPlaySan(String san) {
    final move = San.parse(_board, san, _legal());
    if (move == null) return 'illegal or ambiguous SAN "$san"';
    _apply(move);
    return null;
  }

  /// Returns null while the game is still on.
  GameEnd? checkGameEnd() {
    final legal = _legal();
    if (legal.isEmpty) {
      // _generator.inCheck describes this position because _legal() just generated for it (or cached it).
      if (_generator.inCheck) {
        return GameEnd(
          outcome: whiteToMove ? GameOutcome.blackWin : GameOutcome.whiteWin,
          termination: GameTermination.checkmate,
        );
      }
      return const GameEnd(outcome: GameOutcome.draw, termination: GameTermination.stalemate);
    }
    if (_insufficientMaterial()) {
      return const GameEnd(outcome: GameOutcome.draw, termination: GameTermination.insufficientMaterial);
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

  List<Move> _legal() => _legalCache ??= _generator.generateLegalMoves(_board);

  void _apply(Move move) {
    final uci = _toUci(move);
    final san = San.fromMove(_board, move, _legal());
    _board.makeMove(move);
    _legalCache = null;
    _uciHistory.add(uci);
    _sanHistory.add(san);
    _countRepetition();
  }

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

  /// K v K, K+minor v K, and positions where the only minor pieces are bishops all on the same
  /// colour squares (e.g. K+B v K+B with same-coloured bishops). Neither side can ever mate.
  bool _insufficientMaterial() {
    int knights = 0;
    final bishopSquareColours = <int>{};
    int bishops = 0;
    for (int i = 0; i < 64; i++) {
      final type = Piece.type(_board.position[i]);
      if (type == Piece.pawn || type == Piece.rook || type == Piece.queen) return false;
      if (type == Piece.knight) knights++;
      if (type == Piece.bishop) {
        bishops++;
        bishopSquareColours.add((BoardHelper.getFileFromIndex(i) + BoardHelper.getRankFromIndex(i)) % 2);
      }
    }
    if (knights + bishops <= 1) return true;
    return knights == 0 && bishopSquareColours.length == 1;
  }

  static String? _promotionLetter(Move move) => move.promotion == 0 ? null : ' qnrb'[move.promotion];

  static String _toUci(Move move) =>
      UciMove(from: move.startingSquare, to: move.targetSquare, promotion: _promotionLetter(move)).toString();
}
