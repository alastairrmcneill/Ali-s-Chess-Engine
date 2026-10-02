import 'package:ace/chess_core/game_end.dart';

/// What happened on one engine move.
class MoveStat {
  final int timeMs;
  final int? depth;
  final int? nodes;
  final int? evaluation; // positive = good for White

  const MoveStat(this.timeMs, this.depth, this.nodes, this.evaluation);

  @override
  String toString() {
    return '''MoveStat(
      timeMs: $timeMs,
      depth: $depth,
      nodes: $nodes,
      evaluation: $evaluation)''';
  }
}

class GameRecord {
  final int gameNumber; // 1-based
  final int openingIndex;
  final String startFen;
  final int bookPlies; // the first [bookPlies] moves came from the opening book
  final String whiteId, blackId;
  final String whiteName, blackName;
  final bool engineAIsWhite;
  final GameEnd end;
  final List<String> uciMoves; // every move, book moves included
  final List<String> sanMoves;
  final List<MoveStat> moveStats; // one per ENGINE move, i.e. moves after the book
  final String? errorDetail; // stack trace / referee reason for illegalMove and engineError
  final Duration duration;

  const GameRecord({
    required this.gameNumber,
    required this.openingIndex,
    required this.startFen,
    required this.bookPlies,
    required this.whiteId,
    required this.blackId,
    required this.whiteName,
    required this.blackName,
    required this.engineAIsWhite,
    required this.end,
    required this.uciMoves,
    required this.sanMoves,
    required this.moveStats,
    this.errorDetail,
    required this.duration,
  });

  /// Whether the engine move at [engineMoveIndex] (index into [moveStats]) was played by White.
  /// Games start from the standard position, so White plays the even plies.
  bool engineMoveIsWhite(int engineMoveIndex) => (bookPlies + engineMoveIndex).isEven;

  @override
  String toString() {
    return '''GameRecord(
      gameNumber: $gameNumber, 
      openingIndex: $openingIndex,
      startFen: $startFen,
      bookPlies: $bookPlies,
      whiteId: $whiteId,
      blackId: $blackId,
      whiteName: $whiteName,
      blackName: $blackName,
      engineAIsWhite: $engineAIsWhite,
      end: $end,
      uciMoves: $uciMoves,
      sanMoves: $sanMoves,
      moveStats: $moveStats,
      errorDetail: $errorDetail,
      duration: $duration)''';
  }
}
