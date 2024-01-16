class GameState {
  late int capturedPiece;
  late int enPassantSquare;
  late bool whiteCastleKingSide;
  late bool whiteCastleQueenSide;
  late bool blackCastleKingSide;
  late bool blackCastleQueenSide;
  late int fiftyMoveRule;
  late int zobristKey;

  GameState({
    this.capturedPiece = 0,
    this.enPassantSquare = -1,
    this.whiteCastleKingSide = false,
    this.whiteCastleQueenSide = false,
    this.blackCastleKingSide = false,
    this.blackCastleQueenSide = false,
    this.fiftyMoveRule = 0,
    this.zobristKey = -1,
  });

  @override
  String toString() {
    return "CapturedPieceType: $capturedPiece, En Passant Square: $enPassantSquare, 50 Move Rule: $fiftyMoveRule";
  }
}
