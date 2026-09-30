import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/fen.dart';
import 'package:ace/chess_core/game_result.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/move_generator.dart';
import 'package:ace/chess_core/piece.dart';
import 'package:ace/chess_core/uci.dart';
import 'package:ace/engines/chess_engine.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:flutter/material.dart';

export 'package:ace/chess_core/game_result.dart' show Result;

class GameProvider extends ChangeNotifier {
  Board _board = Board();
  List<Move> _moveHistory = [];
  MoveGenerator _moveGenerator = MoveGenerator();
  int? _selectedIndex;
  Result _gameResult = Result.playing;
  List<Move> _legalMoves = [];
  final ChessEngine _engine = createEngine(latestEngineId);
  bool _engineThinking = false;
  int _thinkingTime = 2000;

  reset() {
    _board = Board();
    _moveGenerator = MoveGenerator();
    _selectedIndex = null;
    _gameResult = Result.playing;
    _legalMoves = [];
    _legalMoves = _moveGenerator.generateLegalMoves(_board);
    _engineThinking = false;
    _moveHistory = [];
    _engine.newGame();
  }

  Board get board => _board;
  Result get gameResult => _gameResult;
  bool get whiteToPlay => _board.whiteToPlay;
  int? get selectedIndex => _selectedIndex;
  List<Move> get legalMoves => _legalMoves;
  bool get engineThinking => _engineThinking;
  Move get lastMove => _moveHistory.isNotEmpty ? _moveHistory.last : Move.invalid;
  int get thinkingTime => _thinkingTime;

  set selectedIndex(int? index) {
    _selectedIndex = index;
    notifyListeners();
  }

  set thinkingTime(int thinkingTime) {
    _thinkingTime = thinkingTime;
    notifyListeners();
  }

  setEngineThinking(bool thinking) {
    _engineThinking = thinking;
  }

  Future select(int index) async {
    // Called when a square on the UI gets tapped or successfully dragged

    if (_selectedIndex != null) {
      // If something has been selected already then try to see if we can move there
      bool result = await move(index);
      if (!result) {
        _selectedIndex = null;
        await select(index);
      }
    } else {
      // If not then set this peiece to be selected, unless its an empty square and set selected to be null
      if (_board.position[index] == Piece.none) {
        _selectedIndex = null;
      } else {
        if ((_board.whiteToPlay && Piece.isColor(_board.position[index], Piece.white)) ||
            (!_board.whiteToPlay && Piece.isColor(_board.position[index], Piece.black))) {
          _selectedIndex = index;
        }
      }
    }
    await updateDisplay();
  }

  Future move(int targetIndex) async {
    // Loop through the moves to find if we can move to this square from where we are

    for (var move in legalMoves) {
      if (move.startingSquare == _selectedIndex && move.targetSquare == targetIndex) {
        _board.makeMove(move);
        _moveHistory.add(move);
        _selectedIndex = null;
        _getGameResult();
        await updateDisplay();

        // This is where we call the engine. Remove to do player v player
        await _aiMove();
        return true;
      }
    }
    await updateDisplay();
    return false;
  }

  Future _aiMove() async {
    // Only play a move if the game is still being played
    if (gameResult == Result.playing) {
      // Update display to give user feedback
      setEngineThinking(true);
      await updateDisplay();

      // Ask the engine for its best move, sending the game so far as FEN + UCI moves
      SearchResult result = await _engine.search(
        EnginePosition(
          startFen: FenPosition.startingFen,
          uciMoves: _moveHistory.map((move) => move.toChessNotation()).toList(),
        ),
        SearchLimits(moveTimeMs: _thinkingTime),
      );
      Move? engineMove = result.bestMove == null ? null : Uci.toLegalMove(_board, result.bestMove!, _moveGenerator);

      // v1 can occasionally suggest an illegal move (see docs/engine_v1_known_issues.md), so never let the game stall
      if (engineMove == null) {
        List<Move> legalMoves = _moveGenerator.generateLegalMoves(_board);
        if (legalMoves.isNotEmpty) engineMove = legalMoves.first;
      }

      // Update display to give user feedback
      setEngineThinking(false);
      await updateDisplay();

      // Make the move
      if (engineMove != null) {
        _board.makeMove(engineMove);
        _moveHistory.add(engineMove);
      }

      // Check the state of the game after the move is made before it is the user's turn again
      _getGameResult();
      notifyListeners();
    }
  }

  Future startAIGame() async {
    // If you want to watch an AI vs AI game
    while (gameResult == Result.playing) {
      await Future.delayed(const Duration(milliseconds: 20));
      await _aiMove();
    }
  }

  bool isMoveValid(int targetIndex) {
    // Used to check if it is valid to drag a piece to the target square
    List<Move> legalMoves = _moveGenerator.generateLegalMoves(board);

    for (Move move in legalMoves) {
      if (move.startingSquare == selectedIndex && move.targetSquare == targetIndex) {
        notifyListeners();
        return true;
      }
    }
    notifyListeners();
    return false;
  }

  _getGameResult() {
    // Check all possible end game conditions
    _legalMoves = _moveGenerator.generateLegalMoves(_board);
    _gameResult = GameResult.check(_board);
  }

  Future updateDisplay() async {
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 30));
  }
}
