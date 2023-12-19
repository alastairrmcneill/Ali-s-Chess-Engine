import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/piece.dart';

class MoveGenerator {
  late List<Move> moves;
  late Board board;
  late List<int> pawnIndexes;
  late List<int> knightIndexes;
  late List<int> kingIndexes;
  late List<int> bisphopIndexes;
  late List<int> rookIndexes;
  late List<int> queenIndexes;

  MoveGenerator() {
    moves = [];
    board = Board();
    pawnIndexes = [];
    knightIndexes = [];
    kingIndexes = [];
    bisphopIndexes = [];
    rookIndexes = [];
    queenIndexes = [];
  }

  List<Move> generateMoves(Board board) {
    this.board = board;
    moves = [];
    findPieces();
    generateKingMoves();
    generateKnightMoves();
    generateBishopMoves();
    generateRookMoves();
    generateQueenMoves();
    // moves.forEach((element) {
    //   print(element);
    // });
    // print(moves.length);
    return moves;
  }

  void findPieces() {
    for (var index = 0; index < board.position.length; index++) {
      int piece = board.position[index];
      int pieceType = Piece.pieceType(piece);
      switch (pieceType) {
        case Piece.king:
          kingIndexes.add(index);
          break;
        case Piece.pawn:
          pawnIndexes.add(index);
          break;
        case Piece.knight:
          knightIndexes.add(index);
          break;
        case Piece.bishop:
          bisphopIndexes.add(index);
          break;
        case Piece.rook:
          rookIndexes.add(index);
          break;
        case Piece.queen:
          queenIndexes.add(index);
          break;
        default:
          break;
      }
    }
  }

  void generateKnightMoves() {
    List<int> jumpMoves = [
      -10,
      -17,
      -15,
      -6,
      10,
      17,
      15,
      6,
    ];

    for (var index in knightIndexes) {
      for (var i = 0; i < jumpMoves.length; i++) {
        int targetIndex = index + jumpMoves[i];
        if (targetIndex >= 0 && targetIndex < 64) {
          int targetIndexCol = targetIndex % 8;
          int startingIndexCol = index % 8;
          if ((targetIndexCol - startingIndexCol).abs() <= 2) {
            if (Piece.color(board.position[index]) != Piece.color(board.position[targetIndex])) {
              Move move = Move(
                startingSquare: index,
                targetSquare: targetIndex,
              );

              moves.add(move);
            }
          }
        }
      }
    }
  }

  void generateKingMoves() {
    List<int> moveOffsets = [
      -8,
      8,
      -1,
      1,
      -7,
      7,
      -9,
      9,
    ];

    for (var index in kingIndexes) {
      for (var i = 0; i < moveOffsets.length; i++) {
        int targetIndex = index + moveOffsets[i];
        if (targetIndex >= 0 && targetIndex < 64) {
          int targetIndexCol = targetIndex % 8;
          int startingIndexCol = index % 8;
          if ((targetIndexCol - startingIndexCol).abs() <= 1) {
            if (Piece.color(board.position[index]) != Piece.color(board.position[targetIndex])) {
              Move move = Move(
                startingSquare: index,
                targetSquare: targetIndex,
              );

              moves.add(move);
            }
          }
        }
      }
    }
  }

  void generateQueenMoves() {
    List<int> moveOffsets = [
      -8,
      8,
      -1,
      1,
      -7,
      7,
      -9,
      9,
    ];

    for (var index in queenIndexes) {
      for (var i = 0; i < moveOffsets.length; i++) {
        int n = 1;
        bool continueSearch = true;
        while (continueSearch) {
          int startingIndex = index + moveOffsets[i] * (n - 1);
          int targetIndex = index + moveOffsets[i] * n;
          if (targetIndex < 0 || targetIndex > 63) break;
          int targetIndexCol = targetIndex % 8;
          int startingIndexCol = startingIndex % 8;
          if ((targetIndexCol - startingIndexCol).abs() > 1) break;
          if (Piece.color(board.position[index]) == Piece.color(board.position[targetIndex])) break;

          Move move = Move(
            startingSquare: index,
            targetSquare: targetIndex,
          );
          moves.add(move);
          if (Piece.pieceType(board.position[targetIndex]) != Piece.none) break;
          n++;
        }
      }
    }
  }

  void generateBishopMoves() {
    List<int> moveOffsets = [
      -7,
      7,
      -9,
      9,
    ];

    for (var index in bisphopIndexes) {
      for (var i = 0; i < moveOffsets.length; i++) {
        int n = 1;
        bool continueSearch = true;
        while (continueSearch) {
          int startingIndex = index + moveOffsets[i] * (n - 1);
          int targetIndex = index + moveOffsets[i] * n;
          if (targetIndex < 0 || targetIndex > 63) break;
          int targetIndexCol = targetIndex % 8;
          int startingIndexCol = startingIndex % 8;
          if ((targetIndexCol - startingIndexCol).abs() > 1) break;
          if (Piece.color(board.position[index]) == Piece.color(board.position[targetIndex])) break;
          Move move = Move(
            startingSquare: index,
            targetSquare: targetIndex,
          );

          moves.add(move);

          n++;
        }
      }
    }
  }

  void generateRookMoves() {
    List<int> moveOffsets = [
      -8,
      8,
      -1,
      1,
    ];

    for (var index in rookIndexes) {
      for (var i = 0; i < moveOffsets.length; i++) {
        int n = 1;
        bool continueSearch = true;
        while (continueSearch) {
          int startingIndex = index + moveOffsets[i] * (n - 1);
          int targetIndex = index + moveOffsets[i] * n;
          if (targetIndex < 0 || targetIndex > 63) break;
          int targetIndexCol = targetIndex % 8;
          int startingIndexCol = startingIndex % 8;
          if ((targetIndexCol - startingIndexCol).abs() > 1) break;
          if (Piece.color(board.position[index]) == Piece.color(board.position[targetIndex])) break;
          Move move = Move(
            startingSquare: index,
            targetSquare: targetIndex,
          );

          moves.add(move);

          n++;
        }
      }
    }
  }
}
