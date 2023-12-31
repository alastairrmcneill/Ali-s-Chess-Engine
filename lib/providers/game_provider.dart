import 'package:ace/chess_engine/ai/evaluation.dart';
import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/ai/engine.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/move_generator.dart';
import 'package:ace/chess_engine/piece.dart';
import 'package:flutter/material.dart';

class GameProvider extends ChangeNotifier {
  Board _board = Board();
  List<Move> _moveHistory = [];
  MoveGenerator _moveGenerator = MoveGenerator();
  int? _selectedIndex = null;
  Result _gameResult = Result.playing;
  List<Move> _legalMoves = [];
  Evaluation _evaluation = Evaluation();
  Engine _engine = Engine();
  bool _engineThinking = false;

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
  int get totalEvaluations => _engine.totalEvaluations;
  int get numNodes => _engine.numNodes;
  int get numQNodes => _engine.numQNodes;
  Duration get searchDuration => _engine.searchDuration;
  bool get engineThinking => _engineThinking;
  Move get lastMove => _moveHistory.isNotEmpty ? _moveHistory.last : Move.invalid();

  set selectedIndex(int? index) {
    _selectedIndex = index;
    notifyListeners();
  }

  setEngineThinking(bool thinking) {
    _engineThinking = thinking;
  }

  Future select(int index) async {
    if (_selectedIndex != null) {
      // If something has been selected already then try to see if we can move there
      bool result = await move(index);
      if (!result) {
        _selectedIndex = null;
        await select(index);
      }
    } else {
      // If not then set this peiece to be selected, unless its an empty square and set selected to be null
      if (_board.position[index] == 0) {
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
    for (var move in legalMoves) {
      if (move.startingSquare == _selectedIndex && move.targetSquare == targetIndex) {
        _board.makeMove(move);
        _moveHistory.add(move);
        // board.unMakeMove(move);
        _selectedIndex = null;
        _getGameResult();
        await updateDisplay();

        await _aiMove();
        return true;
      }
    }
    await updateDisplay();
    return false;
  }

  Future _aiMove() async {
    // Start playing some AI moves?
    if (gameResult == Result.playing) {
      setEngineThinking(true);
      await updateDisplay();

      Move? engineMove = await _engine.getBestMove(board);
      setEngineThinking(false);
      await updateDisplay();

      if (engineMove != null) {
        _board.makeMove(engineMove);
        _moveHistory.add(engineMove);
      }
      _getGameResult();
      notifyListeners();
    }
  }

  Future startAIGame() async {
    while (gameResult == Result.playing) {
      await Future.delayed(Duration(milliseconds: 20));
      await _aiMove();
    }
  }

  bool isMoveValid(int targetIndex) {
    List<Move> legalMoves = _moveGenerator.generateLegalMoves(board);

    for (var move in legalMoves) {
      if (move.startingSquare == selectedIndex && move.targetSquare == targetIndex) {
        notifyListeners();
        return true;
      }
    }
    notifyListeners();
    return false;
  }

  _getGameResult() {
    // Check checkmate and stalemate
    // print("Get Game Result");
    _legalMoves = _moveGenerator.generateLegalMoves(_board);
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
    Map<String, int> occurrenceMap = {};

    for (var list in _board.positionRepetitionHistory) {
      // Convert the list to a string to use as a key in the map
      String key = list.toString();

      // Update the occurrence count for this list
      if (!occurrenceMap.containsKey(key)) {
        occurrenceMap[key] = 1;
      } else {
        occurrenceMap[key] = (occurrenceMap[key] as int) + 1;
      }

      // Check if this list has occurred 3 times
      if (occurrenceMap[key] == 3) {
        _gameResult = Result.repeition;
        return;
      }
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

      int pieceType = Piece.pieceType(piece);
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
