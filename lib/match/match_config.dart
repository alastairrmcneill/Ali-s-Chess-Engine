class MatchConfig {
  final String engineAId, engineBId;
  final int games; // must be even: each opening is played twice with colours swapped
  final Duration moveTime;
  final int maxMoves; // engine moves per side before a draw is declared (300 → 600 plies)
  final String outDir;

  const MatchConfig({
    required this.engineAId,
    required this.engineBId,
    this.games = 1000,
    this.moveTime = const Duration(milliseconds: 100),
    this.maxMoves = 300,
    this.outDir = 'match_results',
  });

  int get maxEnginePlies => maxMoves * 2;

  /// Throws [ArgumentError] if the config can't be run.
  void validate() {
    if (games <= 0 || games.isOdd) throw ArgumentError('games must be a positive even number (got $games)');
    if (moveTime.inMilliseconds <= 0) throw ArgumentError('movetime must be positive');
    if (maxMoves <= 0) throw ArgumentError('max-moves must be positive');
  }
}
