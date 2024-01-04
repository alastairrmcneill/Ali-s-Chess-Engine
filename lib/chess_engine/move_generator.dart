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
  late Set<int> pinnedRayIndexes;
  late bool pinExistsInCurrentPosition;
  late Set<int> checkedRayIndexes;
  late PrecomputeData precomputeData;
  late int friendlyColor;
  late int opponentColor;
  late bool inCheck;
  late bool inDoubleCheck;

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
    pinnedRayIndexes = {};
    pinExistsInCurrentPosition = false;
    checkedRayIndexes = {};
    precomputeData = PrecomputeData();
    friendlyColor = 0;
    opponentColor = 0;
    inCheck = false;
    inDoubleCheck = false;
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
    pinnedRayIndexes = {};
    pinExistsInCurrentPosition = false;
    checkedRayIndexes = {};
    inCheck = false;
    inDoubleCheck = false;
    findPieces();
  }

  List<Move> generateLegalMoves(Board board) {
    this.board = board;
    init();
    generateOpponentAttackData();

    generateKingMoves();
    // If in double check then only the king can move so stop the search
    if (inDoubleCheck) return moves;

    generateRookMoves();
    generateBishopMoves();
    generateQueenMoves();
    generateKnightMoves();
    generatePawnMoves();

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
    int direction = board.whiteToPlay ? -8 : 8;
    int beginningRank = board.whiteToPlay ? 6 : 1;
    int finalRankBeforePromotion = board.whiteToPlay ? 1 : 6;

    for (int startingIndex in friendlyPawnIndexes) {
      int targetIndex = startingIndex + direction;
      int startingRank = rankFromIndex(startingIndex);
      bool oneStepFromPromotion = startingRank == finalRankBeforePromotion;

      // Check forward moves
      if (board.position[targetIndex] == Piece.none) {
        // Check if not pinned or move along pin ray
        if (!pinnedRayIndexes.contains(startingIndex) ||
            isMovingAlongRay(direction, startingIndex, friendlyKingIndex)) {
          // Make sure we aren't in check or if we are that this intercepts check
          if (!inCheck || checkedRayIndexes.contains(targetIndex)) {
            if (oneStepFromPromotion) {
              makePromotionMoves(startingIndex, targetIndex);
            } else {
              moves.add(Move(
                startingSquare: startingIndex,
                targetSquare: targetIndex,
              ));
            }
          }

          if (startingRank == beginningRank) {
            targetIndex = startingIndex + direction * 2;

            if (Piece.color(board.position[targetIndex]) == Piece.none) {
              // Make sure we aren't in check and if we are that this move intercepts
              if (!inCheck || checkedRayIndexes.contains(targetIndex)) {
                moves.add(Move(
                  startingSquare: startingIndex,
                  targetSquare: targetIndex,
                  pawnTwoForward: true,
                ));
              }
            }
          }
        }
      }

      // Check for captures

      // if (!pinnedRayIndexes.contains(startingIndex) ||
      //     isMovingAlongRay(direction - 1, startingIndex, friendlyKingIndex)) {
      //   List<List<int>> pawnCaptureMap =
      //       board.whiteToPlay ? precomputeData.whitePawnCaptures : precomputeData.blackPawnCaptures;
      //   for (int targetCaptureIndex in pawnCaptureMap[startingIndex]) {
      //     if (Piece.isColor(board.position[targetCaptureIndex], opponentColor)) {
      //       // Make sure we aren't in check and if we are that this move intercepts
      //       if (!inCheck || checkedRayIndexes.contains(targetCaptureIndex)) {
      //         if (oneStepFromPromotion) {
      //           makePromotionMoves(startingIndex, targetCaptureIndex);
      //         } else {
      //           moves.add(Move(
      //             startingSquare: startingIndex,
      //             targetSquare: targetCaptureIndex,
      //           ));
      //         }
      //       }
      //     } else if (targetCaptureIndex == board.enPassantSquare) {
      //       if (!inCheckAfterEnPassant(startingIndex, targetCaptureIndex, board.enPassantSquare - direction)) {
      //         moves.add(Move(
      //           startingSquare: startingIndex,
      //           targetSquare: targetCaptureIndex,
      //           enPassantCapture: true,
      //         ));
      //       }
      //     }
      //   }
      // }

      List<List<int>> pawnCaptureMap =
          board.whiteToPlay ? precomputeData.whitePawnCaptures : precomputeData.blackPawnCaptures;

      int targetIndexCaptureLeft = startingIndex + direction - 1;
      int targetIndexCaptureRight = startingIndex + direction + 1;

      // If we aren't pinned or if we are moving along a ray in the left capture direction
      if (!pinnedRayIndexes.contains(startingIndex) ||
          isMovingAlongRay(direction - 1, startingIndex, friendlyKingIndex)) {
        // If its possible for this pawn to attack the target square
        if (pawnCaptureMap[startingIndex].contains(targetIndexCaptureLeft)) {
          if (Piece.isColor(board.position[targetIndexCaptureLeft], opponentColor)) {
            // Make sure we aren't in check and if we are that this move intercepts
            if (!inCheck || checkedRayIndexes.contains(targetIndexCaptureLeft)) {
              if (oneStepFromPromotion) {
                makePromotionMoves(startingIndex, targetIndexCaptureLeft);
              } else {
                moves.add(Move(
                  startingSquare: startingIndex,
                  targetSquare: targetIndexCaptureLeft,
                ));
              }
            }
          } else if (targetIndexCaptureLeft == board.enPassantSquare) {
            if (!inCheckAfterEnPassant(startingIndex, targetIndexCaptureLeft, board.enPassantSquare - direction)) {
              moves.add(Move(
                startingSquare: startingIndex,
                targetSquare: targetIndexCaptureLeft,
                enPassantCapture: true,
              ));
            }
          }
        }
      }

      // If we aren't pinned or if we are moving along a ray in the right capture direction
      if (!pinnedRayIndexes.contains(startingIndex) ||
          isMovingAlongRay(direction + 1, startingIndex, friendlyKingIndex)) {
        if (pawnCaptureMap[startingIndex].contains(targetIndexCaptureRight)) {
          if (Piece.isColor(board.position[targetIndexCaptureRight], opponentColor)) {
            if (!inCheck || checkedRayIndexes.contains(targetIndexCaptureRight)) {
              if (oneStepFromPromotion) {
                makePromotionMoves(startingIndex, targetIndexCaptureRight);
              } else {
                moves.add(Move(
                  startingSquare: startingIndex,
                  targetSquare: targetIndexCaptureRight,
                ));
              }
            }
          } else if (targetIndexCaptureRight == board.enPassantSquare) {
            if (!inCheckAfterEnPassant(startingIndex, targetIndexCaptureRight, board.enPassantSquare - direction)) {
              moves.add(Move(
                startingSquare: startingIndex,
                targetSquare: targetIndexCaptureRight,
                enPassantCapture: true,
              ));
            }
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
      // Can't move it if pinned
      if (pinnedRayIndexes.contains(startingIndex)) continue;

      for (int targetIndex in precomputeData.knightMoves[startingIndex]) {
        int targetPiece = board.position[targetIndex];
        // bool isCapture =  Piece.isColor(targetPiece, opponentColor);

        // Skip if piece is friend OR if we are in check and this piece doesn't get into the check ray
        if (Piece.isColor(targetPiece, friendlyColor) || (inCheck && !checkedRayIndexes.contains(targetIndex))) {
          continue;
        }

        moves.add(
          Move(
            startingSquare: startingIndex,
            targetSquare: targetIndex,
          ),
        );
      }
    }
  }

  void generateKingMoves() {
    int startingIndex = friendlyKingIndex;

    for (int targetIndex in precomputeData.kingMoves[startingIndex]) {
      int pieceOnTargetIndex = board.position[targetIndex];

      // Skip over everything if its a friendly piece on that square
      if (Piece.isColor(pieceOnTargetIndex, friendlyColor)) continue;

      bool isCapture = Piece.isColor(pieceOnTargetIndex, opponentColor);
      if (!isCapture) {
        // If we aren't capturing a piece then we can't go to a square that is in a check ray
        if (checkedRayIndexes.contains(targetIndex)) continue;
      }

      // Is square safe to move to because its not under attack
      if (!opponentAttackMap.contains(targetIndex)) {
        moves.add(
          Move(
            startingSquare: startingIndex,
            targetSquare: targetIndex,
          ),
        );

        // If this square is free can we castle?
        if (!inCheck && !isCapture) {
          int castlingRank = board.whiteToPlay ? 7 : 0;
          // Check Queen Side
          if (targetIndex % 8 == 3 && targetIndex ~/ 8 == castlingRank && canCastleQueenSide()) {
            int castleQueenSideIndex = targetIndex - 1;
            // Check all the squares are empty
            if (board.position[castleQueenSideIndex] == Piece.none &&
                board.position[castleQueenSideIndex - 1] == Piece.none) {
              if (!opponentAttackMap.contains(castleQueenSideIndex)) {
                // Check the final square isn't under attack
                moves.add(
                  Move(
                    startingSquare: startingIndex,
                    targetSquare: castleQueenSideIndex,
                    castling: true,
                  ),
                );
              }
            }
          }

          // Check King Side
          if (targetIndex % 8 == 5 && targetIndex ~/ 8 == castlingRank && canCastleKingSide()) {
            // Try castling right
            int castleKingSideIndex = targetIndex + 1;

            if (board.position[targetIndex] == Piece.none && board.position[castleKingSideIndex] == Piece.none) {
              if (!opponentAttackMap.contains(castleKingSideIndex)) {
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
      }
    }
  }

  int rankFromIndex(int index) {
    return index ~/ 8;
  }

  int fileFromIndex(int index) {
    return index % 8;
  }

  bool inCheckAfterEnPassant(int startingIndex, int targetIndex, int enPassantCaptureIndex) {
    // Simulate playing
    board.position[targetIndex] = board.position[startingIndex];
    board.position[startingIndex] = Piece.none;
    board.position[enPassantCaptureIndex] = Piece.none;

    // Check if in check
    bool isInCheckAfterEnPassant = false;

    int dir = (enPassantCaptureIndex > friendlyKingIndex) ? 1 : 3;
    int currentDirectionOffset = dir == 1 ? 1 : -1;

    for (int n = 1; n <= precomputeData.numSquaresToEdge[friendlyKingIndex][dir]; n++) {
      int index = friendlyKingIndex + (n * currentDirectionOffset);
      int piece = board.position[index];

      if (piece != Piece.none) {
        // If first piece is friendly then stop searching its ok
        if (Piece.isColor(piece, friendlyColor)) break;

        // If the first one we see is an enemy piece then see if it can move along this ray
        if (Piece.isColor(piece, opponentColor)) {
          // Check if rook or queen
          if (Piece.isQueenOrRook(piece)) {
            isInCheckAfterEnPassant = true;
            break;
          } else {
            // If not then this piece is blocking any possible checks stop searching
            break;
          }
        }
      }
    }

    // undo playing
    board.position[targetIndex] = Piece.none;
    board.position[startingIndex] = Piece.pawn | friendlyColor;
    board.position[enPassantCaptureIndex] = Piece.pawn | opponentColor;

    return isInCheckAfterEnPassant;
  }

  bool canCastleQueenSide() {
    return board.whiteToPlay ? board.whiteCastleQueenSide : board.blackCastleQueenSide;
  }

  bool canCastleKingSide() {
    return board.whiteToPlay ? board.whiteCastleKingSide : board.blackCastleKingSide;
  }

  bool isMovingAlongRay(int rayDir, int startingIndex, int targetIndex) {
    int diff = (startingIndex - targetIndex).abs();

    int dir = 1;
    if (diff % 7 == 0) {
      dir = 7;
    } else if (diff % 8 == 0) {
      dir = 8;
    } else if (diff % 9 == 0) {
      dir = 9;
    }

    return dir == rayDir || -1 * dir == rayDir;
  }

  void generateSlidingMoves(int startingIndex, int startingDir, int endingDir) {
    // Is pinned
    bool isPinned = pinnedRayIndexes.contains(startingIndex);

    // If in check and this piece is pinned then you can't move it at all
    if (inCheck && isPinned) return;

    List<int> directionOffsets = [-8, 1, 8, -1, -7, 9, 7, -9];
    // Looping through the different directions
    for (int dir = startingDir; dir < endingDir; dir++) {
      int currentDirectionOffset = directionOffsets[dir];

      // If pinned then this piece can on move along the pin ray and not any other direction
      if (isPinned && !isMovingAlongRay(currentDirectionOffset, friendlyKingIndex, startingIndex)) {
        continue;
      }

      // Find the number of squares in that direction and loop through them
      for (int n = 1; n <= precomputeData.numSquaresToEdge[startingIndex][dir]; n++) {
        int targetIndex = startingIndex + (n * currentDirectionOffset);

        if (Piece.isColor(board.position[targetIndex], friendlyColor)) break; // Your peice

        bool isCapture = board.position[targetIndex] != Piece.none;

        bool movePreventsCheck = checkedRayIndexes.contains(targetIndex);
        if (movePreventsCheck || !inCheck) {
          moves.add(Move(
            startingSquare: startingIndex,
            targetSquare: targetIndex,
          ));
        }

        if (isCapture || movePreventsCheck)
          break; // If you capture a piece you can't keep going past it in this direction
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
        if (targetIndex != friendlyKingIndex) {
          if (board.position[targetIndex] != Piece.none) break;
        }
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

  void generateOpponentAttackData() {
    opponentAttackMap = {};
    pinnedRayIndexes = {};
    pinExistsInCurrentPosition = false;
    checkedRayIndexes = {};
    inCheck = false;
    inDoubleCheck = false;

    //Queen
    for (int startingIndex in opponentQueenIndexes) {
      generateSlidingAttackMap(startingIndex, 0, 8);
    }

    // Rooks
    for (int startingIndex in opponentRookIndexes) {
      generateSlidingAttackMap(startingIndex, 0, 4);
    }

    //Bishops
    for (int startingIndex in opponentBishopIndexes) {
      generateSlidingAttackMap(startingIndex, 4, 8);
    }

    // From the king search out along the lines that sliding pieces could attack
    int startingDir = 0;
    int endingDir = 8;

    if (opponentQueenIndexes.isEmpty) {
      startingDir = opponentRookIndexes.isNotEmpty ? 0 : 4;
      endingDir = opponentBishopIndexes.isNotEmpty ? 8 : 4;
    }

    List<int> directionOffsets = [-8, 1, 8, -1, -7, 9, 7, -9];
    for (int dir = startingDir; dir < endingDir; dir++) {
      // Loop through each direction

      bool isDiagonal = dir > 3;
      int currentDirectionOffset = directionOffsets[dir];
      bool isFriendlyPieceAlongRay = false;
      List<int> rayMask = [];

      for (int n = 1; n <= precomputeData.numSquaresToEdge[friendlyKingIndex][dir]; n++) {
        // Loop to the edge of the board
        int targetIndex = friendlyKingIndex + (n * currentDirectionOffset);
        int piece = board.position[targetIndex];
        rayMask.add(targetIndex);

        // Check if the square contains a peice
        if (piece != Piece.none) {
          // If it contains a friendly piece then might be a pin
          if (Piece.isColor(piece, friendlyColor)) {
            if (!isFriendlyPieceAlongRay) {
              // If this is the first friendly peice along this line then it might be pinned.
              isFriendlyPieceAlongRay = true;
            } else {
              // This is the second friendly piece we have found in this direction, so definitely no pins
              break;
            }
          } else {
            // If it contains an opponent peiece then might be check
            // Check if the peice can move along this direction
            if ((isDiagonal && Piece.isQueenOrBishop(piece)) || !isDiagonal && Piece.isQueenOrRook(piece)) {
              if (isFriendlyPieceAlongRay) {
                // Friendly piece already in the way so its a pin
                pinExistsInCurrentPosition = true;
                pinnedRayIndexes.addAll(rayMask);
              } else {
                // No blockers so this is a check
                checkedRayIndexes.addAll(rayMask);
                inDoubleCheck = inCheck;
                inCheck = true;
              }
              break;
            } else {
              // Piece is an enemy piece that can't move along this direction so is blocking checks or pins
              break;
            }
          }
        }
      }

      // Stop searching if we are in double check
      if (inDoubleCheck) break;
    }

    // Add Knights
    bool isKnightCheck = false;
    for (int startingIndex in opponentKnightIndexes) {
      List<int> knightAttacks = precomputeData.knightMoves[startingIndex];
      opponentAttackMap.addAll(knightAttacks);

      if (!isKnightCheck && knightAttacks.contains(friendlyKingIndex)) {
        isKnightCheck = true;
        inDoubleCheck = inCheck;
        inCheck = true;
        checkedRayIndexes.add(startingIndex);
      }
    }

    // Add pawns
    bool isPawnCheck = false;
    for (int startingIndex in opponentPawnIndexes) {
      List<int> pawnAttacks = [];
      int direction = opponentColor == Piece.white ? -8 : 8;

      // Attack squares
      int targetIndexCaptureLeft = startingIndex + direction - 1;
      int targetIndexCaptureRight = startingIndex + direction + 1;

      if (targetIndexCaptureLeft >= 0 && targetIndexCaptureLeft < 64) {
        int targetIndexCaptureLeftCol = targetIndexCaptureLeft % 8;
        int startingIndexCol = startingIndex % 8;
        if ((targetIndexCaptureLeftCol - startingIndexCol).abs() == 1) {
          pawnAttacks.add(targetIndexCaptureLeft);
        }
      }
      if (targetIndexCaptureRight >= 0 && targetIndexCaptureRight < 64) {
        int targetIndexCaptureRightCol = targetIndexCaptureRight % 8;
        int startingIndexCol = startingIndex % 8;
        if ((targetIndexCaptureRightCol - startingIndexCol).abs() == 1) {
          pawnAttacks.add(targetIndexCaptureRight);
        }
      }

      opponentAttackMap.addAll(pawnAttacks);
      if (!isPawnCheck && pawnAttacks.contains(friendlyKingIndex)) {
        isPawnCheck = true;
        inDoubleCheck = inCheck;
        inCheck = true;
        checkedRayIndexes.add(startingIndex);
      }
    }

    // Add King
    opponentAttackMap.addAll(precomputeData.kingMoves[opponentKingIndex]);
  }
}
