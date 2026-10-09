class MatchConfig {
  final String engineAId;
  final String engineBId;
  final int games;
  final Duration moveTime;

  /// Fixed search depth for both engines. When set, [moveTime] is ignored and games are not timed.
  final int? depth;
  final int maxMoves;

  const MatchConfig({
    required this.engineAId,
    required this.engineBId,
    this.games = 1000,
    this.moveTime = const Duration(milliseconds: 100),
    this.depth,
    this.maxMoves = 300,
  });

  int get maxPlies => maxMoves * 2;
}
