import 'package:ace/chess_engine/core/board.dart';
import 'package:ace/chess_engine/helpers/board_helper.dart';
import 'package:ace/chess_engine/core/move.dart';
import 'package:ace/chess_engine/core/piece.dart';
import 'package:ace/chess_engine/core/precompute_data.dart';

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
  late bool generateQuietMoves;

  MoveGenerator() {
    board = Board();
    precomputeData = PrecomputeData();
    generateQuietMoves = true;
    init();
  }

  void init() {
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
    opponentAttackMap = {};
    checkedRayIndexes = {};
    pinnedRayIndexes = {};
    pinExistsInCurrentPosition = false;
    inCheck = false;
    inDoubleCheck = false;

    findPieces();
  }

  List<Move> generateLegalMoves(Board board, {bool includeQuietMoves = true}) {
    this.board = board;
    generateQuietMoves = includeQuietMoves;
    init();

    // Find where opponent attacks
    generateOpponentAttackData();

    // Check king moves including checks or checkmates
    generateKingMoves();

    // If in double check then only the king can move so stop the search
    if (inDoubleCheck) return moves;

    // Check the rest of the pieces
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
      int pieceType = Piece.type(piece);
      switch (pieceType) {
        case Piece.king:
          Piece.isColor(piece, friendlyColor) ? friendlyKingIndex = index : opponentKingIndex = index;
          break;
        case Piece.pawn:
          Piece.isColor(piece, friendlyColor) ? friendlyPawnIndexes.add(index) : opponentPawnIndexes.add(index);
          break;
        case Piece.knight:
          Piece.isColor(piece, friendlyColor) ? friendlyKnightIndexes.add(index) : opponentKnightIndexes.add(index);
          break;
        case Piece.bishop:
          Piece.isColor(piece, friendlyColor) ? friendlyBishopIndexes.add(index) : opponentBishopIndexes.add(index);
          break;
        case Piece.rook:
          Piece.isColor(piece, friendlyColor) ? friendlyRookIndexes.add(index) : opponentRookIndexes.add(index);
          break;
        case Piece.queen:
          Piece.isColor(piece, friendlyColor) ? friendlyQueenIndexes.add(index) : opponentQueenIndexes.add(index);
          break;
        default:
          break;
      }
    }
  }

  void generateOpponentAttackData() {
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

    // From the king search out along the lines that sliding pieces could attack to find pin rays
    int startingDir = 0;
    int endingDir = 8;

    // If there are no queens then we might not need to search in each direction
    if (opponentQueenIndexes.isEmpty) {
      startingDir = opponentRookIndexes.isNotEmpty ? 0 : 4; // If there are rooks then we need the orthogoal directions
      endingDir = opponentBishopIndexes.isNotEmpty ? 8 : 4; // If there are bishops then we need the diagonal directions
    }

    // Loop through each direction
    for (int dir = startingDir; dir < endingDir; dir++) {
      bool isDiagonal = dir > 3; // Are we looping through the diagonal directions yet
      int currentDirectionOffset = precomputeData.directionOffsets[dir];
      bool isFriendlyPieceAlongRay = false;
      List<int> rayMask = []; // The list of indexes that are along this directional ray

      // Starting from the king square, loop to the edge of the board
      for (int n = 1; n <= precomputeData.numSquaresToEdge[friendlyKingIndex][dir]; n++) {
        int targetIndex = friendlyKingIndex + (n * currentDirectionOffset);
        int piece = board.position[targetIndex];
        rayMask.add(targetIndex);

        // Skip if the square is empty
        if (piece == Piece.none) continue;

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
              // If it is a pin then we need to store all squares between piece and king

              pinExistsInCurrentPosition = true;
              pinnedRayIndexes.addAll(rayMask);
            } else {
              // No blockers so this is a check
              // If it is check then we need to store all squares between piece and king so that later we can decide
              // if a piece can stop check by getting in the way

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

      // Stop searching if we are in double check
      if (inDoubleCheck) break;
    }

    // Add Knights
    bool isKnightCheck = false;
    for (int startingIndex in opponentKnightIndexes) {
      List<int> knightAttacks = precomputeData.knightMoves[startingIndex];
      opponentAttackMap.addAll(knightAttacks);

      // Can only be in check once from a knight so once the first check is found it skips on
      if (!isKnightCheck && knightAttacks.contains(friendlyKingIndex)) {
        isKnightCheck = true;
        inDoubleCheck = inCheck;
        inCheck = true;
        checkedRayIndexes.add(startingIndex);
      }
    }

    // Add pawns
    bool isPawnCheck = false;

    // Select which direction of pawn maps we are looking for
    List<List<int>> pawnCaptureMap =
        opponentColor == Piece.white ? precomputeData.whitePawnCaptures : precomputeData.blackPawnCaptures;

    // Loop through all opponent pawns
    for (int startingIndex in opponentPawnIndexes) {
      List<int> pawnAttacks = pawnCaptureMap[startingIndex];

      // Pull out the attack squares for this starting index

      opponentAttackMap.addAll(pawnAttacks);

      // Does this put us in check
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

  void generateSlidingAttackMap(int startingIndex, int startingDir, int endingDir) {
    // Looping through the different directions
    for (int dir = startingDir; dir < endingDir; dir++) {
      int currentDirectionOffset = precomputeData.directionOffsets[dir];
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

  void generateKingMoves() {
    int startingIndex = friendlyKingIndex;

    for (int targetIndex in precomputeData.kingMoves[startingIndex]) {
      int pieceOnTargetIndex = board.position[targetIndex];

      // Skip over everything if its a friendly piece on that square
      if (Piece.isColor(pieceOnTargetIndex, friendlyColor)) continue;

      bool isCapture = Piece.isColor(pieceOnTargetIndex, opponentColor);
      if (!isCapture) {
        // If we aren't capturing a piece then we can't go to a square that is in a check ray
        if (!generateQuietMoves || checkedRayIndexes.contains(targetIndex)) continue;
      }

      // Skip if square is under attack
      if (opponentAttackMap.contains(targetIndex)) continue;

      moves.add(
        Move(
          startingSquare: startingIndex,
          targetSquare: targetIndex,
        ),
      );

      // Check if we can castle
      if (inCheck || isCapture) continue;

      int castlingRank = board.whiteToPlay ? 7 : 0;
      // Check Queen Side
      if (BoardHelper.getFileFromIndex(targetIndex) == 3 &&
          BoardHelper.getRankFromIndex(targetIndex) == castlingRank &&
          canCastleQueenSide()) {
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
      if (BoardHelper.getFileFromIndex(targetIndex) == 5 &&
          BoardHelper.getRankFromIndex(targetIndex) == castlingRank &&
          canCastleKingSide()) {
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

  void generateQueenMoves() {
    // Loop through all directions
    for (var index in friendlyQueenIndexes) {
      generateSlidingMoves(index, 0, 8);
    }
  }

  void generateBishopMoves() {
    // Loop through only diagonal directions
    for (var index in friendlyBishopIndexes) {
      generateSlidingMoves(index, 4, 8);
    }
  }

  void generateRookMoves() {
    // Loop through only orthogonal direction
    for (var index in friendlyRookIndexes) {
      generateSlidingMoves(index, 0, 4);
    }
  }

  void generateSlidingMoves(int startingIndex, int startingDir, int endingDir) {
    // Is pinned
    bool isPinned = pinnedRayIndexes.contains(startingIndex);

    // If in check and this piece is pinned then you can't move it at all
    if (inCheck && isPinned) return;

    // Looping through the different directions
    for (int dir = startingDir; dir < endingDir; dir++) {
      int currentDirectionOffset = precomputeData.directionOffsets[dir];

      // If pinned then this piece can on move along the pin ray and not any other direction
      if (isPinned && !isMovingAlongRay(currentDirectionOffset, friendlyKingIndex, startingIndex)) continue;

      // Find the number of squares in that direction and loop through them
      for (int n = 1; n <= precomputeData.numSquaresToEdge[startingIndex][dir]; n++) {
        int targetIndex = startingIndex + (n * currentDirectionOffset);
        int targetPiece = board.position[targetIndex];

        if (Piece.isColor(targetPiece, friendlyColor)) break; // Stop searching if you hit friendly peice

        bool isCapture = targetPiece != Piece.none;

        bool movePreventsCheck = checkedRayIndexes.contains(targetIndex);

        // If we aren't in check OR this move prevents check then we can add it
        // If we are in check AND this move doesn't prevent it then skip
        if (inCheck && !movePreventsCheck) continue;

        // For the quiescence search only add moves if its a capture unless we are doing a full search then add all moves
        if (isCapture || generateQuietMoves) {
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

  void generateKnightMoves() {
    for (int startingIndex in friendlyKnightIndexes) {
      // Can't move it if pinned
      if (pinnedRayIndexes.contains(startingIndex)) continue;

      for (int targetIndex in precomputeData.knightMoves[startingIndex]) {
        int targetPiece = board.position[targetIndex];
        bool isCapture = Piece.isColor(targetPiece, opponentColor);

        // For the quiescence search only add moves if its a capture unless we are doing a full search then add all moves
        if (isCapture || generateQuietMoves) {
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
  }

  void generatePawnMoves() {
    int direction = board.whiteToPlay ? -8 : 8;
    int beginningRank = board.whiteToPlay ? 6 : 1;
    int finalRankBeforePromotion = board.whiteToPlay ? 1 : 6;

    for (int startingIndex in friendlyPawnIndexes) {
      int targetIndex = startingIndex + direction;
      int targetPiece = board.position[targetIndex];
      int startingRank = BoardHelper.getRankFromIndex(startingIndex);
      bool oneStepFromPromotion = startingRank == finalRankBeforePromotion;

      // Check forward moves can only be added if we are doing a full search as they will never be a capture
      if (generateQuietMoves) {
        // Can only move forwards if square is empty
        if (targetPiece == Piece.none) {
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

            // Check if pawn can move forwards 2 squares
            if (startingRank == beginningRank) {
              targetIndex = startingIndex + direction * 2;
              targetPiece = board.position[targetIndex];

              if (targetPiece == Piece.none) {
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
      }

      // TODO: Testing pawn changes

      // Check for captures
      List<List<int>> pawnCaptureMap =
          board.whiteToPlay ? precomputeData.whitePawnCaptures : precomputeData.blackPawnCaptures;

      for (int targetIndex in pawnCaptureMap[startingIndex]) {
        int startingFile = BoardHelper.getFileFromIndex(startingIndex);
        int targetFile = BoardHelper.getFileFromIndex(targetIndex);
        int directionOffset = targetFile - startingFile;

        // If we are pinned AND not moving along a ray in the correct direction then skip
        if (pinnedRayIndexes.contains(startingIndex) &&
            !isMovingAlongRay(direction + directionOffset, startingIndex, friendlyKingIndex)) continue;

        // If its possible for this pawn to attack the target square
        if (Piece.isColor(board.position[targetIndex], opponentColor)) {
          // If we are in check and this move doesn't intercept it then skip
          if (inCheck && !checkedRayIndexes.contains(targetIndex)) continue;

          if (oneStepFromPromotion) {
            makePromotionMoves(startingIndex, targetIndex);
          } else {
            moves.add(Move(
              startingSquare: startingIndex,
              targetSquare: targetIndex,
            ));
          }
        } else if (targetIndex == board.enPassantSquare) {
          // If we are in check after en passant then skip
          if (inCheckAfterEnPassant(startingIndex, targetIndex, board.enPassantSquare - direction)) continue;

          moves.add(Move(
            startingSquare: startingIndex,
            targetSquare: targetIndex,
            enPassantCapture: true,
          ));
        }
      }
    }
  }

  void makePromotionMoves(int startingIndex, int targetIndex) {
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

      // Skip if square is empty
      if (piece == Piece.none) continue;

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
}
