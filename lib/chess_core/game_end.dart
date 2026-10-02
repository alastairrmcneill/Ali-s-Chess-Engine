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
  maxMoves, // our move cap of 300 moves
  illegalMove, // our engine returned an illegal move
  engineError // our engine encountered an error
}

class GameEnd {
  final GameOutcome outcome;
  final GameTermination termination;
  final String? detail;

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
}
