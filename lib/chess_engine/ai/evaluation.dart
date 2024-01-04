import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/piece.dart';

class Evaluation {
  final int pawnValue = 100;
  final int knightValue = 300;
  final int bishopValue = 300;
  final int rookValue = 500;
  final int queenValue = 900;

  late Board board;
  late List<int> whitePawnIndexes;
  late List<int> blackPawnIndexes;
  late List<int> whiteKnightIndexes;
  late List<int> blackKnightIndexes;
  late List<int> whiteBishopIndexes;
  late List<int> blackBishopIndexes;
  late List<int> whiteRookIndexes;
  late List<int> blackRookIndexes;
  late List<int> whiteQueenIndexes;
  late List<int> blackQueenIndexes;

  int evaluate(Board board) {
    this.board = board;
    init();
    int whiteEval = 0;
    int blackEval = 0;

    whiteEval += whitePawnIndexes.length * pawnValue +
        whiteKnightIndexes.length * knightValue +
        whiteBishopIndexes.length * bishopValue +
        whiteRookIndexes.length * rookValue +
        whiteQueenIndexes.length * queenValue;
    blackEval += blackPawnIndexes.length * pawnValue +
        blackKnightIndexes.length * knightValue +
        blackBishopIndexes.length * bishopValue +
        blackRookIndexes.length * rookValue +
        blackQueenIndexes.length * queenValue;

    return whiteEval - blackEval;
  }

  init() {
    whitePawnIndexes = [];
    blackPawnIndexes = [];
    blackKnightIndexes = [];
    whiteKnightIndexes = [];
    whiteBishopIndexes = [];
    blackBishopIndexes = [];
    whiteRookIndexes = [];
    blackRookIndexes = [];
    whiteQueenIndexes = [];
    blackQueenIndexes = [];
    findPieces();
  }

  void findPieces() {
    for (var index = 0; index < board.position.length; index++) {
      int piece = board.position[index];
      int pieceType = Piece.pieceType(piece);

      switch (pieceType) {
        case Piece.pawn:
          Piece.isColor(piece, Piece.white) ? whitePawnIndexes.add(index) : blackPawnIndexes.add(index);
          break;
        case Piece.knight:
          Piece.isColor(piece, Piece.white) ? whiteKnightIndexes.add(index) : blackKnightIndexes.add(index);
          break;
        case Piece.bishop:
          Piece.isColor(piece, Piece.white) ? whiteBishopIndexes.add(index) : blackBishopIndexes.add(index);
          break;
        case Piece.rook:
          Piece.isColor(piece, Piece.white) ? whiteRookIndexes.add(index) : blackRookIndexes.add(index);
          break;
        case Piece.queen:
          Piece.isColor(piece, Piece.white) ? whiteQueenIndexes.add(index) : blackQueenIndexes.add(index);
          break;
        default:
          break;
      }
    }
  }
}
