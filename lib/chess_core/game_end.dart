enum GameOutcome {
  whiteWin,
  blackWin,
  draw,
}

enum GameTermination {
  checkmate,
  stalemate,
  threefoldRepetition,
  fiftyMoveRule,
  insufficientMaterial,
  maxMoves, // our move cap
  illegalMove, // an engine returned a move the referee rejected
  engineError, // an engine threw or returned no move
}

class GameEnd {
  final GameOutcome outcome;
  final GameTermination termination;
  final String? detail; // human-readable, for logs and the PGN

  const GameEnd({
    required this.outcome,
    required this.termination,
    this.detail,
  });

  String get pgnResult => switch (outcome) {
        GameOutcome.whiteWin => "1-0",
        GameOutcome.blackWin => "0-1",
        GameOutcome.draw => "1/2-1/2",
      };

  @override
  String toString() => '${termination.name} ($pgnResult)${detail == null ? '' : ': $detail'}';
}
