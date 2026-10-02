import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:flutter/material.dart';

class GameProvider extends ChangeNotifier {
  // No move cap in the app: only the normal chess rules end a game.
  static const int _noMoveCap = 1 << 30;

  Referee _referee = Referee(Referee.standardStartFen, maxPlies: _noMoveCap);
  String _engineId = EngineRegistry.latestId;
  ChessEngine _engine = EngineRegistry.create(EngineRegistry.latestId);
  GameEnd? _gameEnd;
  int? _selectedIndex;
  bool _engineThinking = false;
  int _thinkingTime = 2000;
  String? _engineProblem;
  int _gameId = 0; // bumped on reset, so a search from an old game is ignored

  void reset() {
    _referee = Referee(Referee.standardStartFen, maxPlies: _noMoveCap);
    _engine.newGame();
    _gameEnd = null;
    _selectedIndex = null;
    _engineThinking = false;
    _engineProblem = null;
    _gameId++;
    notifyListeners();
  }

  // Engine version picker
  List<String> get engineIds => EngineRegistry.versionIds;
  String get engineId => _engineId;

  void setEngine(String id) {
    if (id == _engineId) return;
    _engineId = id;
    _engine = EngineRegistry.create(id);
    reset();
  }

  GameEnd? get gameEnd => _gameEnd;
  bool get isPlaying => _gameEnd == null;
  bool get whiteToPlay => _referee.whiteToMove;
  int? get selectedIndex => _selectedIndex;
  bool get engineThinking => _engineThinking;
  int get thinkingTime => _thinkingTime;
  String? get engineProblem => _engineProblem;

  /// Piece code on [index] (a8 = 0 … h1 = 63), using chess_core's piece codes.
  int pieceAt(int index) => _referee.pieceAt(index);

  /// Squares the piece on [index] can legally move to.
  List<int> legalTargetsFrom(int index) {
    final from = BoardHelper.squareName(index);
    return _referee
        .legalUciMoves()
        .where((uci) => uci.startsWith(from))
        .map((uci) => BoardHelper.squareIndex(uci.substring(2, 4)))
        .toSet()
        .toList();
  }

  ({int from, int to})? get lastMove {
    final history = _referee.uciHistory;
    if (history.isEmpty) return null;
    final last = history.last;
    return (from: BoardHelper.squareIndex(last.substring(0, 2)), to: BoardHelper.squareIndex(last.substring(2, 4)));
  }

  set selectedIndex(int? index) {
    _selectedIndex = index;
    notifyListeners();
  }

  set thinkingTime(int thinkingTime) {
    _thinkingTime = thinkingTime;
    notifyListeners();
  }

  /// Called when a square is tapped.
  Future<void> select(int index) async {
    if (_engineThinking || !isPlaying) return;

    if (_selectedIndex != null && legalTargetsFrom(_selectedIndex!).contains(index)) {
      await move(index);
      return;
    }

    final piece = pieceAt(index);
    final ownPiece = Piece.isColor(piece, whiteToPlay ? Piece.white : Piece.black);
    _selectedIndex = ownPiece ? index : null;
    notifyListeners();
  }

  /// Plays the selected piece to [targetIndex], then lets the engine reply.
  Future<bool> move(int targetIndex) async {
    final from = _selectedIndex;
    if (from == null || _engineThinking || !isPlaying) return false;

    final uci = BoardHelper.squareName(from) + BoardHelper.squareName(targetIndex);
    final candidates = _referee.legalUciMoves().where((m) => m.startsWith(uci)).toList();
    if (candidates.isEmpty) {
      _selectedIndex = null;
      notifyListeners();
      return false;
    }
    // Promotions auto-queen, as before.
    final chosen = candidates.length == 1 ? candidates.first : candidates.firstWhere((m) => m.endsWith('q'));

    _referee.tryPlayUci(chosen);
    _selectedIndex = null;
    _gameEnd = _referee.checkGameEnd();
    notifyListeners();

    await _aiMove();
    return true;
  }

  bool isMoveValid(int targetIndex) {
    final from = _selectedIndex;
    return from != null && legalTargetsFrom(from).contains(targetIndex);
  }

  Future<void> _aiMove() async {
    if (!isPlaying) return;
    final gameId = _gameId;

    _engineThinking = true;
    notifyListeners();
    // Let the UI draw "thinking" before the search hogs the main isolate.
    await Future.delayed(const Duration(milliseconds: 30));

    String? problem;
    try {
      final result = await _engine.getMove(
        _referee.startFen,
        _referee.uciHistory,
        SearchLimits(moveTime: Duration(milliseconds: _thinkingTime)),
      );
      if (gameId != _gameId) return; // the game was reset while the engine was thinking
      problem = _referee.tryPlayUci(result.uciMove);
    } catch (e) {
      if (gameId != _gameId) return;
      problem = '$e';
    }

    if (problem != null) {
      _engineProblem = '${_engine.displayName}: $problem';
      debugPrint(_engineProblem);
    }
    _engineThinking = false;
    _gameEnd = _referee.checkGameEnd();
    notifyListeners();
  }

  /// The selected engine plays both sides.
  Future<void> startAIGame() async {
    while (isPlaying && _engineProblem == null) {
      final gameId = _gameId;
      await _aiMove();
      if (gameId != _gameId) return;
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }
}
