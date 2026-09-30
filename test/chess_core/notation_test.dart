import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/fen.dart';
import 'package:ace/chess_core/game_result.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/san.dart';
import 'package:ace/chess_core/uci.dart';
import 'package:flutter_test/flutter_test.dart';

Board playUci(String fen, List<String> moves) {
  Board board = Board.fromFen(fen);
  for (String uci in moves) {
    board.makeMove(Uci.toLegalMove(board, uci)!);
  }
  return board;
}

void main() {
  group("FEN", () {
    test("round trips the starting position", () {
      expect(Board().toFen(), FenPosition.startingFen);
    });

    test("parses en passant square and clocks", () {
      FenPosition fen = FenPosition.parse("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3");
      expect(fen.enPassantSquare, 21); // f6
      expect(fen.halfmoveClock, 0);
      expect(fen.fullmoveNumber, 3);

      Board board = Board.fromFen("8/8/8/4k3/8/8/8/4K3 b - - 37 80");
      expect(board.fiftyMoveRule, 37);
      expect(board.toFen(), "8/8/8/4k3/8/8/8/4K3 b - - 37 80");
    });

    test("accepts EPD positions without clocks", () {
      expect(Board.fromFen("4k3/8/8/8/8/8/8/4K3 w - -").toFen(), "4k3/8/8/8/8/8/8/4K3 w - - 0 1");
    });

    test("writes en passant square and clocks after moves", () {
      expect(playUci(FenPosition.startingFen, ["e2e4"]).toFen(),
          "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1");
      expect(playUci(FenPosition.startingFen, ["g1f3", "g8f6"]).toFen(),
          "rnbqkb1r/pppppppp/5n2/8/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 2 2");
    });

    test("rejects nonsense", () {
      expect(() => FenPosition.parse("not a fen"), throwsFormatException);
      expect(() => FenPosition.parse("8/8/8/8/8/8/8/9 w - - 0 1"), throwsFormatException);
    });
  });

  group("UCI", () {
    test("parses special moves into legal moves", () {
      Board castle = Board.fromFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
      expect(Uci.toLegalMove(castle, "e1g1")!.castling, isTrue);
      expect(Uci.toLegalMove(castle, "e1c1")!.castling, isTrue);

      Board enPassant = Board.fromFen("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3");
      expect(Uci.toLegalMove(enPassant, "e5f6")!.enPassantCapture, isTrue);

      Board promotion = Board.fromFen("8/4P3/8/8/8/8/k7/4K3 w - - 0 1");
      Move underPromotion = Uci.toLegalMove(promotion, "e7e8n")!;
      expect(underPromotion.promotion, 2);
      expect(Uci.fromMove(underPromotion), "e7e8n");
    });

    test("rejects illegal and malformed moves", () {
      expect(Uci.toLegalMove(Board(), "e2e5"), isNull);
      expect(Uci.toLegalMove(Board(), "e7e8"), isNull);
      expect(Uci.toLegalMove(Board(), "zz"), isNull);
    });
  });

  group("SAN", () {
    test("writes and reads common moves", () {
      Board board = Board();
      expect(San.fromMove(board, Uci.toLegalMove(board, "g1f3")!), "Nf3");
      expect(San.toLegalMove(board, "e4")!.toChessNotation(), "e2e4");

      // Knights on b1 and f3 can both reach d2, so the file is needed
      Board ambiguous = Board.fromFen("4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1");
      expect(San.fromMove(ambiguous, Uci.toLegalMove(ambiguous, "b1d2")!), "Nbd2");

      Board mate = Board.fromFen("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1");
      expect(San.fromMove(mate, Uci.toLegalMove(mate, "a1a8")!), "Ra8#");

      Board castle = Board.fromFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
      expect(San.fromMove(castle, Uci.toLegalMove(castle, "e1c1")!), "O-O-O");
      expect(San.toLegalMove(castle, "0-0")!.toChessNotation(), "e1g1");

      Board promotion = Board.fromFen("3r3k/4P3/8/8/8/8/8/K7 w - - 0 1");
      expect(San.fromMove(promotion, Uci.toLegalMove(promotion, "e7d8q")!), "exd8=Q+");
    });
  });

  group("Game result", () {
    test("detects checkmate and stalemate", () {
      expect(GameResult.check(Board.fromFen("R5k1/5ppp/8/8/8/8/8/6K1 b - - 1 1")), Result.blackIsMated);
      expect(GameResult.check(Board.fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")), Result.stalemate);
      expect(GameResult.check(Board()), Result.playing);
    });

    test("detects the fifty move rule and insufficient material", () {
      expect(GameResult.check(Board.fromFen("4k3/8/8/8/8/8/4P3/4K3 w - - 100 80")), Result.fiftyMoveRule);
      expect(GameResult.check(Board.fromFen("4k3/8/8/8/8/8/8/4KN2 w - - 0 1")), Result.insufficientMaterial);
      expect(GameResult.check(Board.fromFen("4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1")), Result.insufficientMaterial);
      expect(GameResult.check(Board.fromFen("4k1b1/8/8/8/8/8/8/2B1K3 w - - 0 1")), Result.playing);
      expect(GameResult.check(Board.fromFen("4k3/8/8/8/8/8/8/3NKN2 w - - 0 1")), Result.playing);
    });

    test("detects three fold repetition of the current position, counting the start position", () {
      List<String> shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"];
      expect(GameResult.check(playUci(FenPosition.startingFen, shuffle)), Result.playing);
      expect(GameResult.check(playUci(FenPosition.startingFen, [...shuffle, ...shuffle])), Result.repetition);
    });
  });
}
