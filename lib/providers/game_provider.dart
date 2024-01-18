import 'package:ace/chess_engine/ai/evaluation.dart';
import 'package:ace/chess_engine/core/board.dart';
import 'package:ace/chess_engine/ai/engine.dart';
import 'package:ace/chess_engine/core/move.dart';
import 'package:ace/chess_engine/core/move_generator.dart';
import 'package:ace/chess_engine/core/piece.dart';
import 'package:ace/chess_engine/core/zobrist.dart';
import 'package:flutter/material.dart';

class GameProvider extends ChangeNotifier {
  Zobrist zobrist = Zobrist(); // Needed to initialise the zobrist values before hashing can begin
  Board _board = Board();
  List<Move> _moveHistory = [];
  MoveGenerator _moveGenerator = MoveGenerator();
  int? _selectedIndex = null;
  Result _gameResult = Result.playing;
  List<Move> _legalMoves = [];
  Evaluation _evaluation = Evaluation();
  Engine _engine = Engine();
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
  }

  Board get board => _board;
  MoveGenerator get moveGenerator => _moveGenerator;
  Result get gameResult => _gameResult;
  bool get whiteToPlay => _board.whiteToPlay;
  int? get selectedIndex => _selectedIndex;
  List<Move> get legalMoves => _legalMoves;
  int get currentEval => _evaluation.evaluate(_board);
  bool get engineThinking => _engineThinking;
  Move get lastMove => _moveHistory.isNotEmpty ? _moveHistory.last : Move.invalid;
  int get zobristKey => _board.zobristKey;
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

      // Find best move in this position
      Move? engineMove = await _engine.getBestMove(board, _thinkingTime);

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

    // Check if stalemate or checkmate
    if (legalMoves.isEmpty) {
      if (_moveGenerator.opponentAttackMap.contains(_moveGenerator.friendlyKingIndex)) {
        _gameResult = _board.whiteToPlay ? Result.whiteIsMated : Result.blackIsMated;
        return;
      }
      _gameResult = Result.stalemate;
      return;
    }

    // Check 50 moves
    if (_board.fiftyMoveRule >= 100) {
      _gameResult = Result.fiftyMoveRule;
      return;
    }

    // Check 3 repetition
    if (_board.hashHistory.values.any((element) => element >= 3)) {
      _gameResult = Result.repeition;

      return;
    }

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
      _gameResult = Result.insufficientMaterial;
      return;
    } else if (numPawns + numRooks + numQueens == 0) {
      if ((numKnights == 1 && numBishops == 0) || (numBishops == 1 && numKnights == 0)) {
        _gameResult = Result.insufficientMaterial;
        return;
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
          _gameResult = Result.insufficientMaterial;
          return;
        }
      }
    }

    // If all pass then we are still playing
    _gameResult = Result.playing;
  }

  Future updateDisplay() async {
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 30));
  }
}

enum Result {
  playing,
  whiteIsMated,
  blackIsMated,
  stalemate,
  repeition,
  fiftyMoveRule,
  insufficientMaterial,
}
