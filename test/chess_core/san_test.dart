import 'dart:math';

import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:ace/chess_core/rules/zobrist.dart';
import 'package:ace/chess_core/san.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = FenPosition.startingPosition;

Board _board(String fen, [List<String> moves = const []]) {
  final board = Board.fromFEN(fen);
  for (final uci in moves) {
    board.makeMove(_find(board, uci));
  }
  return board;
}

Move _find(Board board, String uci) {
  final parsed = UciMove.parse(uci);
  return MoveGenerator().generateLegalMoves(board).firstWhere((m) =>
      m.startingSquare == parsed.from &&
      m.targetSquare == parsed.to &&
      (m.promotion == 0 ? null : ' qnrb'[m.promotion]) == parsed.promotion);
}

String _san(String fen, String uci, [List<String> moves = const []]) {
  final board = _board(fen, moves);
  return San.fromMove(board, _find(board, uci), MoveGenerator().generateLegalMoves(board));
}

void main() {
  setUpAll(() => Zobrist());

  group('San.fromMove', () {
    test('simple moves', () {
      expect(_san(_start, 'g1f3'), 'Nf3');
      expect(_san(_start, 'e2e4'), 'e4');
    });
    test('file disambiguation', () {
      const fen = '4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1';
      expect(_san(fen, 'b1d2'), 'Nbd2');
      expect(_san(fen, 'f3d2'), 'Nfd2');
    });
    test('rank disambiguation', () {
      const fen = '4k3/8/8/R7/8/8/8/R3K3 w - - 0 1';
      expect(_san(fen, 'a1a3'), 'R1a3');
      expect(_san(fen, 'a5a3'), 'R5a3');
    });
    test('file and rank disambiguation', () {
      const fen = '4k3/8/8/8/8/Q1Q5/8/Q3K3 w - - 0 1';
      expect(_san(fen, 'a1b2'), 'Q1b2');
      expect(_san(fen, 'a3b2'), 'Qa3b2');
      expect(_san(fen, 'c3b2'), 'Qcb2');
    });
    test('pawn captures and en passant', () {
      expect(_san(_start, 'e4d5', ['e2e4', 'd7d5']), 'exd5');
      expect(_san(_start, 'e5d6', ['e2e4', 'a7a6', 'e4e5', 'd7d5']), 'exd6');
    });
    test('promotions', () {
      const fen = 'r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1';
      expect(_san(fen, 'b7b8q'), 'b8=Q+');
      expect(_san(fen, 'b7a8n'), 'bxa8=N');
    });
    test('castling and mate', () {
      expect(_san(_start, 'e1g1', ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6']), 'O-O');
      expect(_san(_start, 'd8h4', ['f2f3', 'e7e5', 'g2g4']), 'Qh4#');
    });
  });

  group('San.parse', () {
    test('accepts annotations and alternative spellings', () {
      final board = _board(_start);
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.parse(board, 'Nf3+', legal), isNotNull);
      expect(San.parse(board, 'Nf4', legal), isNull);
      expect(San.parse(board, 'e4!?', legal), isNotNull);

      final castleBoard = _board(_start, ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6']);
      expect(San.parse(castleBoard, '0-0', MoveGenerator().generateLegalMoves(castleBoard))?.castling, isTrue);

      final promoBoard = _board('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1');
      expect(San.parse(promoBoard, 'b8Q', MoveGenerator().generateLegalMoves(promoBoard))?.promotion, 1);
    });

    test('rejects ambiguous SAN', () {
      final board = _board('4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1');
      expect(San.parse(board, 'Nd2', MoveGenerator().generateLegalMoves(board)), isNull);
    });
  });

  test('round trip: parse(fromMove(m)) == m for every legal move in 20 random games', () {
    final random = Random(42);
    for (int game = 0; game < 20; game++) {
      final referee = Referee(_start, maxPlies: 200);
      final board = Board.fromFEN(_start);
      while (referee.checkGameEnd() == null) {
        final legal = MoveGenerator().generateLegalMoves(board);
        for (final move in legal) {
          final san = San.fromMove(board, move, legal);
          final parsed = San.parse(board, san, legal);
          expect(identical(parsed, move), isTrue, reason: 'SAN "$san" did not round-trip');
        }
        final uci = referee.legalUciMoves()[random.nextInt(legal.length)];
        referee.tryPlayUci(uci);
        board.makeMove(_find(board, uci));
      }
    }
  });
}
