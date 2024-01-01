import 'package:ace/chess_engine/board.dart';
import 'package:ace/chess_engine/move.dart';
import 'package:ace/chess_engine/piece.dart';
import 'package:ace/chess_engine/precompute_data.dart';

class MoveGenerator {
  late List<Move> moves;
  late Board board;
  late List<int> friendlyPawnIndexes;
  late List<int> opponentPawnIndexes;
  late List<int> friendlyKnightIndexes;
  late List<int> opponentKnightIndexes;
  late int friendlyKingIndex;
  late int opponentKingIndex;
  late List<int> friendlyBishopIndexes;
  late List<int> opponentBishopIndexes;
  late List<int> friendlyRookIndexes;
  late List<int> opponentRookIndexes;
  late List<int> friendlyQueenIndexes;
  late List<int> opponentQueenIndexes;
  late Set<int> opponentAttackMap;
  late PrecomputeData precomputeData;
  late int friendlyColor;
  late int opponentColor;
  late bool inCheck;

  MoveGenerator() {
    moves = [];
    board = Board();
    friendlyPawnIndexes = [];
    opponentPawnIndexes = [];
    friendlyKnightIndexes = [];
    opponentKnightIndexes = [];
    friendlyKingIndex = -1;
    opponentKingIndex = -1;
    friendlyBishopIndexes = [];
    opponentBishopIndexes = [];
    friendlyRookIndexes = [];
    opponentRookIndexes = [];
    friendlyQueenIndexes = [];
    opponentQueenIndexes = [];
    opponentAttackMap = {};
    precomputeData = PrecomputeData();
    friendlyColor = 0;
    opponentColor = 0;
    inCheck = false;
  }

  init() {
    friendlyColor = board.whiteToPlay ? Piece.white : Piece.black;
    opponentColor = board.whiteToPlay ? Piece.black : Piece.white;
    moves = [];
    friendlyPawnIndexes = [];
    opponentPawnIndexes = [];
    friendlyKnightIndexes = [];
    opponentKnightIndexes = [];
    friendlyKingIndex = -1;
    opponentKingIndex = -1;
    friendlyBishopIndexes = [];
    opponentBishopIndexes = [];
    friendlyRookIndexes = [];
    opponentRookIndexes = [];
    friendlyQueenIndexes = [];
    opponentQueenIndexes = [];
    inCheck = false;
    findPieces();
    generateOpponentAttackMap();
  }

  List<Move> generateLegalMoves(Board board) {
    generateOpponentAttackMap();
    List<Move> legalMoves = [];
    List<Move> psuedoLegalMoves = generateMoves(board);

    for (Move moveToverify in psuedoLegalMoves) {
      board.makeMove(moveToverify);

      List<Move> responses = generateMoves(board);
      if (responses.any((move) => move.targetSquare == opponentKingIndex)) {
        // If any of the response contain the square the king is on then its not a legal move, so skip.
        board.unMakeMove(moveToverify);
        continue;
      }

      if (moveToverify.castling) {
        if (board.whiteToPlay) {
          // Then we are checking if white are attacking black king
          if (responses.any((move) => move.targetSquare == 4) || opponentAttackMap.contains(4)) {
            // If the king was in check when they started trying to castle it's not legal
            board.unMakeMove(moveToverify);
            continue;
          }
          if (moveToverify.targetSquare == 2) {
            // Check the middle squre
            if (responses.any((move) => move.targetSquare == 3) || opponentAttackMap.contains(3)) {
              // If the king moves through check then its not legal
              board.unMakeMove(moveToverify);
              continue;
            }
            // if there is a pawn attacking those squares
          } else if (moveToverify.targetSquare == 6) {
            if (responses.any((move) => move.targetSquare == 5) || opponentAttackMap.contains(5)) {
              // If the king moves through check then its not legal
              board.unMakeMove(moveToverify);
              continue;
            }
          }
        } else {
          // Then we are checking if black are attacking white king
          if (responses.any((move) => move.targetSquare == 60) || opponentAttackMap.contains(60)) {
            // If the king was in check when they started trying to castle it's not legal
            board.unMakeMove(moveToverify);
            continue;
          }
          if (moveToverify.targetSquare == 62) {
            // Check the middle squre
            if (responses.any((move) => move.targetSquare == 61) || opponentAttackMap.contains(61)) {
              // If the king moves through check then its not legal
              board.unMakeMove(moveToverify);
              continue;
            }
          } else if (moveToverify.targetSquare == 58) {
            if (responses.any((move) => move.targetSquare == 59) || opponentAttackMap.contains(59)) {
              // If the king moves through check then its not legal
              board.unMakeMove(moveToverify);
              continue;
            }
          }
        }
      }

      // If all those tests pass then its a legal move

      legalMoves.add(moveToverify);
      board.unMakeMove(moveToverify);
    }
    // for (Move move in legalMoves) print(move);
    // print("---------------------------------");
    findPieces();
    generateOpponentAttackMap();

    return legalMoves;
  }

  List<Move> generateMoves(Board board) {
    this.board = board;
    init();

    generatePawnMoves();
    generateKingMoves();
    generateKnightMoves();
    generateBishopMoves();
    generateRookMoves();
    generateQueenMoves();
    // for (Move move in moves) {
    //   print(move.toString());
    // }

    return moves;
  }

  void findPieces() {
    for (var index = 0; index < board.position.length; index++) {
      int piece = board.position[index];
      int pieceType = Piece.pieceType(piece);

      if (Piece.isColor(piece, friendlyColor)) {
        switch (pieceType) {
          case Piece.king:
            friendlyKingIndex = index;
            break;
          case Piece.pawn:
            friendlyPawnIndexes.add(index);
            break;
          case Piece.knight:
            friendlyKnightIndexes.add(index);
            break;
          case Piece.bishop:
            friendlyBishopIndexes.add(index);
            break;
          case Piece.rook:
            friendlyRookIndexes.add(index);
            break;
          case Piece.queen:
            friendlyQueenIndexes.add(index);
            break;
          default:
            break;
        }
      } else if (Piece.isColor(piece, opponentColor)) {
        switch (pieceType) {
          case Piece.king:
            opponentKingIndex = index;
            break;
          case Piece.pawn:
            opponentPawnIndexes.add(index);
            break;
          case Piece.knight:
            opponentKnightIndexes.add(index);
            break;
          case Piece.bishop:
            opponentBishopIndexes.add(index);
            break;
          case Piece.rook:
            opponentRookIndexes.add(index);
            break;
          case Piece.queen:
            opponentQueenIndexes.add(index);
            break;
          default:
            break;
        }
      }
    }
  }

  void generatePawnMoves() {
    for (var index in friendlyPawnIndexes) {
      int direction = Piece.isColor(board.position[index], Piece.white) ? -8 : 8;
      int finalRankBeforePromotion = Piece.isColor(board.position[index], Piece.white) ? 1 : 6;

      int targetIndex = index + direction;
      int startingRank = index ~/ 8;
      bool oneStepFromPromotion = startingRank == finalRankBeforePromotion;
      // Check forward moves
      if (Piece.pieceType(board.position[targetIndex]) == Piece.none) {
        if (targetIndex >= 0 && targetIndex < 64) {
          int targetIndexCol = targetIndex % 8;
          int startingIndexCol = index % 8;
          if ((targetIndexCol - startingIndexCol).abs() <= 2) {
            if (Piece.pieceType(board.position[targetIndex]) == Piece.none) {
              if (oneStepFromPromotion) {
                makePromotionMoves(index, targetIndex);
              } else {
                Move move = Move(
                  startingSquare: index,
                  targetSquare: targetIndex,
                );

                moves.add(move);
              }
            }
          }
        }

        if (index ~/ 8 == 1 || index ~/ 8 == 6) {
          targetIndex = index + direction * 2;
          if (targetIndex >= 0 && targetIndex < 64) {
            int targetIndexCol = targetIndex % 8;
            int startingIndexCol = index % 8;
            if ((targetIndexCol - startingIndexCol).abs() <= 2) {
              if (Piece.color(board.position[targetIndex]) == Piece.none) {
                Move move = Move(
                  startingSquare: index,
                  targetSquare: targetIndex,
                  pawnTwoForward: true,
                );

                moves.add(move);
              }
            }
          }
        }
      }

      // Check for captures
      int targetIndexCaptureLeft = index + direction - 1;
      int targetIndexCaptureRight = index + direction + 1;

      if (targetIndexCaptureLeft >= 0 && targetIndexCaptureLeft < 64) {
        int targetIndexCaptureLeftCol = targetIndexCaptureLeft % 8;
        int startingIndexCol = index % 8;
        if ((targetIndexCaptureLeftCol - startingIndexCol).abs() == 1) {
          if (Piece.isColor(board.position[targetIndexCaptureLeft], opponentColor)) {
            if (oneStepFromPromotion) {
              makePromotionMoves(index, targetIndexCaptureLeft);
            } else {
              moves.add(Move(
                startingSquare: index,
                targetSquare: targetIndexCaptureLeft,
              ));
            }
          } else if (targetIndexCaptureLeft == board.enPassantSquare) {
            // print("adding en passant capture");
            moves.add(Move(
              startingSquare: index,
              targetSquare: targetIndexCaptureLeft,
              enPassantCapture: true,
            ));
          }
        }
      }
      if (targetIndexCaptureRight >= 0 && targetIndexCaptureRight < 64) {
        int targetIndexCaptureRightCol = targetIndexCaptureRight % 8;
        int startingIndexCol = index % 8;
        if ((targetIndexCaptureRightCol - startingIndexCol).abs() == 1) {
          if (Piece.isColor(board.position[targetIndexCaptureRight], opponentColor)) {
            if (oneStepFromPromotion) {
              makePromotionMoves(index, targetIndexCaptureRight);
            } else {
              moves.add(Move(
                startingSquare: index,
                targetSquare: targetIndexCaptureRight,
              ));
            }
          } else if (targetIndexCaptureRight == board.enPassantSquare) {
            // print("adding en passant capture");
            moves.add(Move(
              startingSquare: index,
              targetSquare: targetIndexCaptureRight,
              enPassantCapture: true,
            ));
          }
        }
      }
    }
  }

  makePromotionMoves(int startingIndex, int targetIndex) {
    moves.add(Move(
      startingSquare: startingIndex,
      targetSquare: targetIndex,
      promotion: 1, // Queen
    ));

    moves.add(Move(
      startingSquare: startingIndex,
      targetSquare: targetIndex,
      promotion: 2, // Knight
    ));
    moves.add(Move(
      startingSquare: startingIndex,
      targetSquare: targetIndex,
      promotion: 3, // Rook
    ));
    moves.add(Move(
      startingSquare: startingIndex,
      targetSquare: targetIndex,
      promotion: 4, // Bishop
    ));
  }

  void generateKnightMoves() {
    for (int startingIndex in friendlyKnightIndexes) {
      for (int targetIndex in precomputeData.knightMoves[startingIndex]) {
        if (!Piece.isColor(board.position[targetIndex], friendlyColor)) {
          moves.add(
            Move(
              startingSquare: startingIndex,
              targetSquare: targetIndex,
            ),
          );
        }
      }
    }
  }

  void generateKingMoves() {
    int startingIndex = friendlyKingIndex;

    for (int targetIndex in precomputeData.kingMoves[startingIndex]) {
      if (!Piece.isColor(board.position[targetIndex], friendlyColor)) {
        moves.add(
          Move(
            startingSquare: startingIndex,
            targetSquare: targetIndex,
          ),
        );
      }

      int castlingRank = board.whiteToPlay ? 7 : 0;
      // Check Castling
      if (targetIndex % 8 == 3 && targetIndex ~/ 8 == castlingRank && canCastleQueenSide()) {
        // Try Castling Left
        int castleQueenSideIndex = targetIndex - 1;

        if (board.position[targetIndex] == Piece.none &&
            board.position[castleQueenSideIndex] == Piece.none &&
            board.position[castleQueenSideIndex - 1] == Piece.none) {
          // Check if starting square or middle square are attacked

          moves.add(
            Move(
              startingSquare: startingIndex,
              targetSquare: castleQueenSideIndex,
              castling: true,
            ),
          );
        }
      }
      if (targetIndex % 8 == 5 && targetIndex ~/ 8 == castlingRank && canCastleKingSide()) {
        // Try castling right
        int castleKingSideIndex = targetIndex + 1;

        if (board.position[targetIndex] == Piece.none && board.position[castleKingSideIndex] == Piece.none) {
          // Check if starting square is attacked
          moves.add(
            Move(
              startingSquare: startingIndex,
              targetSquare: castleKingSideIndex,
              castling: true,
            ),
          );
        }
      }
    }
  }

  bool canCastleQueenSide() {
    return board.whiteToPlay ? board.whiteCastleQueenSide : board.blackCastleQueenSide;
  }

  bool canCastleKingSide() {
    return board.whiteToPlay ? board.whiteCastleKingSide : board.blackCastleKingSide;
  }

  void generateSlidingMoves(int startingIndex, int startingDir, int endingDir) {
    List<int> directionOffsets = [-8, 1, 8, -1, -7, 9, 7, -9];
    // Looping through the different directions
    for (int dir = startingDir; dir < endingDir; dir++) {
      int currentDirectionOffset = directionOffsets[dir];
      // Find the number of squares in that direction and loop through them
      for (int n = 1; n <= precomputeData.numSquaresToEdge[startingIndex][dir]; n++) {
        int targetIndex = startingIndex + (n * currentDirectionOffset);

        if (Piece.isColor(board.position[targetIndex], friendlyColor)) break; // Your peice

        bool isCapture = board.position[targetIndex] != Piece.none;

        moves.add(Move(
          startingSquare: startingIndex,
          targetSquare: targetIndex,
        ));
        if (isCapture) break; // If you capture a piece you can't keep going past it in this direction
      }
    }
  }

  void generateQueenMoves() {
    for (var index in friendlyQueenIndexes) {
      generateSlidingMoves(index, 0, 8);
    }
  }

  void generateBishopMoves() {
    for (var index in friendlyBishopIndexes) {
      generateSlidingMoves(index, 4, 8);
    }
  }

  void generateRookMoves() {
    for (var index in friendlyRookIndexes) {
      generateSlidingMoves(index, 0, 4);
    }
  }

  void generateSlidingAttackMap(int startingIndex, int startingDir, int endingDir) {
    List<int> directionOffsets = [-8, 1, 8, -1, -7, 9, 7, -9];
    // Looping through the different directions
    for (int dir = startingDir; dir < endingDir; dir++) {
      int currentDirectionOffset = directionOffsets[dir];
      // Find the number of squares in that direction and loop through them
      for (int n = 1; n <= precomputeData.numSquaresToEdge[startingIndex][dir]; n++) {
        int targetIndex = startingIndex + (n * currentDirectionOffset);

        opponentAttackMap.add(targetIndex);
        if (board.position[targetIndex] != Piece.none) break;
      }
    }
  }

  void generateOpponentAttackMap() {
    opponentAttackMap = {};
    //Queen
    for (int startingIndex in friendlyQueenIndexes) {
      generateSlidingAttackMap(startingIndex, 0, 8);
    }

    // Rooks
    for (int startingIndex in friendlyRookIndexes) {
      generateSlidingAttackMap(startingIndex, 0, 4);
    }

    //Bishops
    for (int startingIndex in friendlyBishopIndexes) {
      generateSlidingAttackMap(startingIndex, 4, 8);
    }

    // Knight attack maps
    for (int startingIndex in friendlyKnightIndexes) {
      for (int targetIndex in precomputeData.knightMoves[startingIndex]) {
        opponentAttackMap.add(targetIndex);
      }
    }

    // Pawn attack maps
    for (int index in friendlyPawnIndexes) {
      int direction = Piece.isColor(board.position[index], Piece.white) ? -8 : 8;

      // Attack squares
      int targetIndexCaptureLeft = index + direction - 1;
      int targetIndexCaptureRight = index + direction + 1;

      if (targetIndexCaptureLeft >= 0 && targetIndexCaptureLeft < 64) {
        int targetIndexCaptureLeftCol = targetIndexCaptureLeft % 8;
        int startingIndexCol = index % 8;
        if ((targetIndexCaptureLeftCol - startingIndexCol).abs() == 1) {
          opponentAttackMap.add(targetIndexCaptureLeft);
        }
      }
      if (targetIndexCaptureRight >= 0 && targetIndexCaptureRight < 64) {
        int targetIndexCaptureRightCol = targetIndexCaptureRight % 8;
        int startingIndexCol = index % 8;
        if ((targetIndexCaptureRightCol - startingIndexCol).abs() == 1) {
          opponentAttackMap.add(targetIndexCaptureRight);
        }
      }
    }
    // print(opponentAttackMap);
    // opponentAttackMap = {};
  }
}
