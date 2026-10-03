class MatchConfig {
  final String engineAId;
  final String engineBId;
  final int games;
  final Duration moveTime;
  final int maxMoves;

  const MatchConfig({
    required this.engineAId,
    required this.engineBId,
    this.games = 1000,
    this.moveTime = const Duration(milliseconds: 100),
    this.maxMoves = 300,
  });

  int get maxPlies => maxMoves * 2;
}
