class Piece {
  static const int none = 0;
  static const int king = 1;
  static const int pawn = 2;
  static const int knight = 3;
  static const int bishop = 4;
  static const int rook = 5;
  static const int queen = 6;

  static const int white = 0;
  static const int black = 8;

  // Pieces using bitwise OR
  static const int whiteKing = king | white;
  static const int whitePawn = pawn | white;
  static const int whiteKnight = knight | white;
  static const int whiteBishop = bishop | white;
  static const int whiteRook = rook | white;
  static const int whiteQueen = queen | white;
  static const int blackKing = king | black;
  static const int blackPawn = pawn | black;
  static const int blackKnight = knight | black;
  static const int blackBishop = bishop | black;
  static const int blackRook = rook | black;
  static const int blackQueen = queen | black;

  // Piece list
  static const int maxPieceIndex = blackQueen;
  static const List<int> pieceList = [
    whiteKing,
    whitePawn,
    whiteKnight,
    whiteBishop,
    whiteRook,
    whiteQueen,
    blackKing,
    blackPawn,
    blackKnight,
    blackBishop,
    blackRook,
    blackQueen
  ];

  // Masks
  static const int typeMask = 7;
  static const int colorMask = 1 << 3; // 0b1000

  static bool isColor(int piece, int color) {
    return (piece & colorMask) == color && piece != 0;
  }

  static int color(int piece) {
    return piece & colorMask;
  }

  static int type(int piece) {
    return piece & typeMask;
  }

  static bool isQueenOrBishop(int piece) {
    int pieceType = Piece.type(piece);
    return (pieceType == queen || pieceType == bishop);
  }

  static bool isQueenOrRook(int piece) {
    int pieceType = Piece.type(piece);
    return (pieceType == queen || pieceType == rook);
  }

  static const String _fenLetters = " kpnbrq";

  /// FEN letter for a piece, uppercase for white (e.g. 'N'), lowercase for black
  static String toFenChar(int piece) {
    String letter = _fenLetters[type(piece)];
    return isColor(piece, white) ? letter.toUpperCase() : letter;
  }

  static int fromFenChar(String letter) {
    int pieceType = _fenLetters.indexOf(letter.toLowerCase());
    if (pieceType <= 0) throw FormatException("Unknown piece", letter);
    return pieceType | (letter == letter.toUpperCase() ? white : black);
  }
}
