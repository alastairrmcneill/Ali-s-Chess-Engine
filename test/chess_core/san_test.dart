import 'dart:math';

import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/notation/san.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds the legal move matching a UCI string, the same way the referee does.
Move _findMove(List<Move> legal, String uci) {
  final parsed = UciMove.parse(uci);
  return legal.firstWhere(
    (m) =>
        m.startingSquare == parsed.from &&
        m.targetSquare == parsed.to &&
        (m.promotion == 0 ? null : ' qnrb'[m.promotion]) == parsed.promotion,
  );
}

/// A board reached by playing [uciMoves] from the starting position.
Board _playBoard(List<String> uciMoves) {
  final board = Board.fromFEN(FenPosition.startingPosition);
  for (final uci in uciMoves) {
    final legal = MoveGenerator().generateLegalMoves(board);
    board.makeMove(_findMove(legal, uci));
  }
  return board;
}

void main() {
  group('San.fromMove', () {
    test('simple knight and pawn moves from the start', () {
      final board = Board.fromFEN(FenPosition.startingPosition);
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'g1f3'), legal), 'Nf3');
      expect(San.fromMove(board, _findMove(legal, 'e2e4'), legal), 'e4');
    });

    test('file disambiguation between two knights', () {
      final board = Board.fromFEN('4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1');
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'b1d2'), legal), 'Nbd2');
      expect(San.fromMove(board, _findMove(legal, 'f3d2'), legal), 'Nfd2');
    });

    test('rank disambiguation between two rooks', () {
      final board = Board.fromFEN('4k3/8/8/R7/8/8/8/R3K3 w - - 0 1');
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'a1a3'), legal), 'R1a3');
      expect(San.fromMove(board, _findMove(legal, 'a5a3'), legal), 'R5a3');
    });

    test('full square disambiguation between three queens', () {
      final board = Board.fromFEN('4k3/8/8/8/8/Q1Q5/8/Q3K3 w - - 0 1');
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'a1b2'), legal), 'Q1b2');
      expect(San.fromMove(board, _findMove(legal, 'a3b2'), legal), 'Qa3b2');
      expect(San.fromMove(board, _findMove(legal, 'c3b2'), legal), 'Qcb2');
    });

    test('pawn capture', () {
      final board = _playBoard(['e2e4', 'd7d5']);
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'e4d5'), legal), 'exd5');
    });

    test('en passant capture', () {
      final board = _playBoard(['e2e4', 'a7a6', 'e4e5', 'd7d5']);
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'e5d6'), legal), 'exd6');
    });

    test('promotion and underpromotion capture', () {
      final board = Board.fromFEN('r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1');
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'b7b8q'), legal), 'b8=Q+');
      expect(San.fromMove(board, _findMove(legal, 'b7a8n'), legal), 'bxa8=N');
    });

    test('kingside castling', () {
      final board = _playBoard(['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6']);
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'e1g1'), legal), 'O-O');
    });

    test('checkmate suffix', () {
      final board = _playBoard(['f2f3', 'e7e5', 'g2g4']);
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.fromMove(board, _findMove(legal, 'd8h4'), legal), 'Qh4#');
    });
  });

  group('San.toLegalMove', () {
    test('accepts a check suffix, castling with zeros, no-equals promotion, and annotation glyphs', () {
      final start = Board.fromFEN(FenPosition.startingPosition);
      final startLegal = MoveGenerator().generateLegalMoves(start);
      expect(San.toLegalMove(start, 'Nf3+', startLegal)?.isSameAs(_findMove(startLegal, 'g1f3')), isTrue);

      final castleBoard = _playBoard(['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6']);
      final castleLegal = MoveGenerator().generateLegalMoves(castleBoard);
      expect(San.toLegalMove(castleBoard, '0-0', castleLegal)?.isSameAs(_findMove(castleLegal, 'e1g1')), isTrue);

      final promoBoard = Board.fromFEN('k7/4P3/8/8/8/8/8/4K3 w - - 0 1');
      final promoLegal = MoveGenerator().generateLegalMoves(promoBoard);
      expect(San.toLegalMove(promoBoard, 'e8Q', promoLegal)?.isSameAs(_findMove(promoLegal, 'e7e8q')), isTrue);

      final captureBoard = _playBoard(['e2e4', 'd7d5']);
      final captureLegal = MoveGenerator().generateLegalMoves(captureBoard);
      expect(San.toLegalMove(captureBoard, 'exd5!?', captureLegal)?.isSameAs(_findMove(captureLegal, 'e4d5')), isTrue);
    });

    test('returns null for an illegal move', () {
      final board = Board.fromFEN(FenPosition.startingPosition);
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.toLegalMove(board, 'Nf4', legal), isNull);
    });

    test('returns null for an ambiguous move missing its disambiguation', () {
      final board = Board.fromFEN('4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1');
      final legal = MoveGenerator().generateLegalMoves(board);
      expect(San.toLegalMove(board, 'Nd2', legal), isNull);
    });

    test('round trip: every legal move\'s SAN parses back to the same move', () {
      final random = Random(42);
      for (int game = 0; game < 20; game++) {
        final board = Board.fromFEN(FenPosition.startingPosition);
        for (int ply = 0; ply < 200; ply++) {
          final legal = MoveGenerator().generateLegalMoves(board);
          if (legal.isEmpty) break;
          for (final move in legal) {
            final san = San.fromMove(board, move, legal);
            final parsed = San.toLegalMove(board, san, legal);
            expect(parsed, isNotNull, reason: 'failed to parse $san back to a move');
            expect(parsed!.isSameAs(move), isTrue, reason: '$san parsed to a different move');
          }
          board.makeMove(legal[random.nextInt(legal.length)]);
        }
      }
    });
  });
}
