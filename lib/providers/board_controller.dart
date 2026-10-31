import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:flutter/foundation.dart';

/// What [BoardView] needs from a game: the position, whose pieces the local player controls and a way to play
/// a move. Piece selection is shared here so the engine game and the online game behave the same.
mixin BoardController on ChangeNotifier {
  int? _selectedIndex;

  List<int> get position;
  List<Move> get legalMoves;
  Move? get lastMove;
  bool get playerIsWhite;

  /// Whether the local player may move right now.
  bool get isHumanTurn;
  void playHumanMove(Move move);

  int get playerColor => playerIsWhite ? Piece.white : Piece.black;
  int? get selectedIndex => _selectedIndex;

  /// Drops the selection without notifying, for use while the implementer is already about to notify.
  @protected
  void resetSelection() => _selectedIndex = null;

  bool canPickUp(int index) {
    if (!isHumanTurn) return false;
    final piece = position[index];
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
      legalMoves.where((m) => m.startingSquare == from && m.targetSquare == to).toList();

  bool isTargetOfSelected(int index) {
    final from = _selectedIndex;
    return from != null && isHumanTurn && movesBetween(from, index).isNotEmpty;
  }
}
