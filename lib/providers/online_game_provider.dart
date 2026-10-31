import 'dart:async';

import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/online/online_game.dart';
import 'package:ace/online/online_game_backend.dart';
import 'package:ace/providers/board_controller.dart';
import 'package:flutter/foundation.dart';

/// A game against another person over the network. The server holds the list of moves; this replays them
/// through a local [Referee] to get the position and legal moves, and checks the opponent's moves are legal.
class OnlineGameProvider extends ChangeNotifier with BoardController {
  final OnlineGameBackend _backend;
  final String userId;
  OnlineGame _game;
  Referee _referee = Referee(Referee.standardStartFen);
  GameEnd? _boardEnd;
  StreamSubscription<OnlineGame?>? _subscription;
  final StreamController<String> _notices = StreamController<String>.broadcast();

  /// True while our move has been played locally but the server hasn't confirmed it yet.
  bool _sending = false;
  bool _disposed = false;

  /// A problem that stops play until the next successful refresh.
  String? _error;

  OnlineGameProvider({required OnlineGameBackend backend, required this.userId, required OnlineGame game})
      : _backend = backend,
        _game = game {
    _syncBoard();
    _subscription = _backend.watch(game.id).listen((update) {
      if (update == null) {
        unawaited(refresh());
      } else {
        _apply(update);
      }
    });
  }

  OnlineGame get game => _game;
  String? get error => _error;

  /// One-off messages for the user, e.g. a request the server rejected.
  Stream<String> get notices => _notices.stream;
  bool get sending => _sending;
  List<String> get sanHistory => _referee.sanHistory;
  String? get opponentName => _game.opponentName(userId);
  bool get drawOfferedToMe => _game.drawOfferedBy != null && _game.drawOfferedBy != userId;
  bool get drawOfferedByMe => _game.drawOfferedBy == userId;

  @override
  List<int> get position => _referee.position;
  @override
  List<Move> get legalMoves => _referee.legalMoves;
  @override
  bool get playerIsWhite => _game.isWhite(userId);

  @override
  Move? get lastMove {
    final history = _referee.uciHistory;
    if (history.isEmpty) return null;
    final uci = UciMove.parse(history.last);
    return Move(startingSquare: uci.from, targetSquare: uci.to);
  }

  @override
  bool get isHumanTurn =>
      _game.status == OnlineGameStatus.active &&
      !_sending &&
      _error == null &&
      _referee.whiteToMove == playerIsWhite &&
      _boardEnd == null;

  bool get isFinished => _game.status == OnlineGameStatus.finished || _game.status == OnlineGameStatus.cancelled;

  /// The final result, from the server once it has recorded one, otherwise from the board.
  OnlineResult? get result {
    final serverResult = _game.result;
    if (serverResult != null) return OnlineResult(serverResult, _game.termination ?? '');
    final end = _boardEnd;
    return end == null ? null : OnlineResult(end.pgnResult, end.termination.name);
  }

  @override
  void playHumanMove(Move move) {
    if (!isHumanTurn) return;
    final uci = _toUci(move);
    final ply = _referee.pliesPlayed;
    if (_referee.tryPlayUci(uci) != null) return;
    resetSelection();
    final end = _boardEnd = _referee.checkGameEnd();
    _sending = true;
    notifyListeners();
    unawaited(_send(() => _backend.playMove(
          _game.id,
          uci: uci,
          ply: ply,
          result: end?.pgnResult,
          termination: end?.termination.name,
        )));
  }

  Future<void> resign() => _send(() => _backend.resign(_game.id));
  Future<void> offerDraw() => _send(() => _backend.offerDraw(_game.id));
  Future<void> answerDraw(bool accept) => _send(() => _backend.answerDraw(_game.id, accept: accept));
  Future<void> cancel() => _send(() => _backend.cancel(_game.id));

  /// Refetches the game, e.g. after reconnecting or a failed request.
  Future<void> refresh() async {
    try {
      final game = await _backend.fetchGame(_game.id);
      if (_disposed) return;
      _apply(game, force: true);
    } catch (e) {
      if (_disposed) return;
      _error = 'Connection problem: $e';
      notifyListeners();
    }
  }

  Future<void> _send(Future<OnlineGame> Function() request) async {
    try {
      final game = await request();
      if (_disposed) return;
      _sending = false;
      _apply(game);
    } catch (e) {
      if (_disposed) return;
      _sending = false;
      _notices.add(e is OnlineGameException ? e.message : 'Connection problem: $e');
      notifyListeners();
      // Whatever we tried may or may not have happened, so start again from what the server says.
      await refresh();
    }
  }

  void _apply(OnlineGame game, {bool force = false}) {
    // Realtime events can arrive after the response to a later request, so never step backwards.
    if (!force && game.updatedAt.isBefore(_game.updatedAt)) return;
    _game = game;
    if (force) _error = null;
    _syncBoard();
    notifyListeners();
  }

  /// Brings the local board in line with the server's moves.
  void _syncBoard() {
    final server = _game.moves;
    final local = _referee.uciHistory;
    final localIsPrefix = local.length <= server.length && listEquals(local, server.sublist(0, local.length));

    // Our own move is on the board but not on the server yet.
    if (_sending && !localIsPrefix && listEquals(server, local.sublist(0, server.length))) return;

    if (!localIsPrefix) {
      _referee = Referee(Referee.standardStartFen);
      resetSelection();
    }
    for (final uci in server.skip(_referee.pliesPlayed)) {
      if (_referee.tryPlayUci(uci) != null) {
        _error = 'Your opponent sent an illegal move ($uci)';
        break;
      }
      resetSelection();
    }
    _boardEnd = _referee.checkGameEnd();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _notices.close();
    super.dispose();
  }

  static String _toUci(Move move) => UciMove(
        from: move.startingSquare,
        to: move.targetSquare,
        promotion: move.promotion == 0 ? null : ' qnrb'[move.promotion],
      ).toString();
}

class OnlineResult {
  /// "1-0", "0-1" or "1/2-1/2".
  final String pgn;

  /// A [GameTermination] name, 'resignation' or 'agreement'.
  final String termination;

  const OnlineResult(this.pgn, this.termination);

  bool get isDraw => pgn == '1/2-1/2';
  bool get whiteWon => pgn == '1-0';

  String get reason => switch (termination) {
        'checkmate' => 'by checkmate',
        'stalemate' => 'by stalemate',
        'threefoldRepetition' => 'by threefold repetition',
        'fiftyMoveRule' => 'by the fifty-move rule',
        'insufficientMaterial' => 'by insufficient material',
        'maxMoves' => 'by move limit',
        'resignation' => 'by resignation',
        'agreement' => 'by agreement',
        _ => '',
      };

  static GameOutcome outcomeOf(String pgn) => switch (pgn) {
        '1-0' => GameOutcome.whiteWin,
        '0-1' => GameOutcome.blackWin,
        _ => GameOutcome.draw,
      };
}
