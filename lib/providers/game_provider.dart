import 'dart:async';

import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/services/engine_worker.dart';
import 'package:flutter/foundation.dart';

class GameSettings {
  final String engineId;
  final Duration moveTime;
  final bool playerIsWhite;

  const GameSettings({required this.engineId, required this.moveTime, required this.playerIsWhite});

  String get engineName => EngineRegistry.create(engineId).displayName;
}

class GameProvider extends ChangeNotifier {
  GameSettings? _settings;
  late Referee _referee;
  late Board _board;
  final MoveGenerator _moveGenerator = MoveGenerator();
  List<Move> _legalMoves = [];
  Move? _lastMove;
  int? _selectedIndex;
  GameEnd? _gameEnd;

  EngineWorker? _worker;
  StreamSubscription<SearchStats>? _statsSubscription;
  bool _engineThinking = false;
  SearchStats? _stats;
  int _searchesCompleted = 0;

  /// Bumped on every (re)start and exit so results from a superseded game are ignored.
  int _generation = 0;

  GameSettings? get settings => _settings;
  List<int> get position => _board.position;
  List<Move> get legalMoves => _legalMoves;
  Move? get lastMove => _lastMove;
  int? get selectedIndex => _selectedIndex;
  GameEnd? get gameEnd => _gameEnd;
  bool get engineThinking => _engineThinking;
  SearchStats? get stats => _stats;
  int get searchesCompleted => _searchesCompleted;
  int get generation => _generation;
  bool get playerIsWhite => _settings?.playerIsWhite ?? true;
  int get playerColor => playerIsWhite ? Piece.white : Piece.black;
  bool get isHumanTurn => _worker != null && _gameEnd == null && !_engineThinking && _board.whiteToPlay == playerIsWhite;

  /// Engine evaluation in centipawns from White's point of view (the engine reports it for the side to move).
  int? get evalForWhite {
    final eval = _stats?.eval;
    if (eval == null) return null;
    return playerIsWhite ? -eval : eval;
  }

  Future<void> startGame(GameSettings settings) async {
    _teardown();
    final generation = ++_generation;
    _settings = settings;

    // The referee initialises the zobrist tables, so it has to be created before the board.
    _referee = Referee(Referee.standardStartFen);
    _board = Board.fromFEN(Referee.standardStartFen);
    _legalMoves = _moveGenerator.generateLegalMoves(_board);
    _lastMove = null;
    _selectedIndex = null;
    _gameEnd = null;
    _stats = null;
    _searchesCompleted = 0;
    _engineThinking = false;
    notifyListeners();

    final worker = await EngineWorker.spawn(settings.engineId);
    if (generation != _generation) {
      worker.dispose();
      return;
    }
    _worker = worker;
    _statsSubscription = worker.stats.listen((stats) {
      _stats = stats;
      notifyListeners();
    });

    if (!isHumanTurn) unawaited(_engineTurn());
  }

  Future<void> restart() => startGame(_settings!);

  /// Stops the engine and discards the game. Doesn't notify, so it is safe to call from `dispose`.
  void endGame() {
    _teardown();
    _generation++;
    _settings = null;
  }

  void _teardown() {
    _statsSubscription?.cancel();
    _statsSubscription = null;
    _worker?.dispose();
    _worker = null;
    _engineThinking = false;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  bool canPickUp(int index) {
    if (!isHumanTurn) return false;
    final piece = _board.position[index];
    return piece != Piece.none && Piece.isColor(piece, playerColor);
  }

  void select(int index) {
    if (!isHumanTurn) return;
    _selectedIndex = canPickUp(index) && _selectedIndex != index ? index : null;
    notifyListeners();
  }

  /// Like [select] but never deselects, so starting a drag on the already selected piece keeps it selected.
  void pickUp(int index) {
    if (!canPickUp(index) || _selectedIndex == index) return;
    _selectedIndex = index;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedIndex == null) return;
    _selectedIndex = null;
    notifyListeners();
  }

  /// Legal moves from [from] to [to]. More than one means the move is a promotion and a piece must be chosen.
  List<Move> movesBetween(int from, int to) =>
      _legalMoves.where((m) => m.startingSquare == from && m.targetSquare == to).toList();

  bool isTargetOfSelected(int index) {
    final from = _selectedIndex;
    return from != null && isHumanTurn && movesBetween(from, index).isNotEmpty;
  }

  void playHumanMove(Move move) {
    if (!isHumanTurn) return;
    _applyMove(move);
  }

  void _applyMove(Move move) {
    _referee.tryPlayUci(_toUci(move));
    _board.makeMove(move);
    _lastMove = move;
    _selectedIndex = null;
    _legalMoves = _moveGenerator.generateLegalMoves(_board);
    _gameEnd = _referee.checkGameEnd();
    notifyListeners();

    if (_gameEnd == null && !isHumanTurn) unawaited(_engineTurn());
  }

  Future<void> _engineTurn() async {
    final worker = _worker;
    if (worker == null) return;
    final generation = _generation;

    _engineThinking = true;
    _stats = null;
    notifyListeners();

    try {
      final result = await worker.search(_referee.startFen, List.of(_referee.uciHistory), _settings!.moveTime);
      if (generation != _generation) return;
      _engineThinking = false;
      _searchesCompleted++;

      final move = _legalMoves.where((m) => _toUci(m) == result.uciMove).firstOrNull;
      if (move == null) {
        _endWithEngineFailure(GameTermination.illegalMove, 'Engine played ${result.uciMove}');
        return;
      }
      _applyMove(move);
    } catch (e) {
      if (generation != _generation) return;
      _engineThinking = false;
      _endWithEngineFailure(GameTermination.engineError, e.toString());
    }
  }

  void _endWithEngineFailure(GameTermination termination, String detail) {
    _gameEnd = GameEnd(
      outcome: playerIsWhite ? GameOutcome.whiteWin : GameOutcome.blackWin,
      termination: termination,
      detail: detail,
    );
    notifyListeners();
  }

  static String _toUci(Move move) => UciMove(
        from: move.startingSquare,
        to: move.targetSquare,
        promotion: move.promotion == 0 ? null : ' qnrb'[move.promotion],
      ).toString();
}
