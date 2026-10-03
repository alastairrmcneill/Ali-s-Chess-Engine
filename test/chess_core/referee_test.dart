import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legal move is applied and recorded', () {
    final referee = Referee(FenPosition.startingPosition);
    expect(referee.tryPlayUci('e2e4'), isNull);
    expect(referee.uciHistory, ['e2e4']);
    expect(referee.sanHistory, ['e4']);
  });

  test('illegal move is rejected and history is unchanged', () {
    final referee = Referee(FenPosition.startingPosition);
    expect(referee.tryPlayUci('e2e5'), isNotNull);
    expect(referee.uciHistory, isEmpty);
  });

  test('malformed moves are rejected', () {
    final referee = Referee(FenPosition.startingPosition);
    for (final uci in ['E2E4', 'e2', 'e7e8k']) {
      expect(referee.tryPlayUci(uci), isNotNull, reason: uci);
    }
  });

  test('promotion is strict about requiring a promotion piece', () {
    const fen = '4k3/1P6/8/8/8/8/8/4K3 w - - 0 1';
    expect(Referee(fen).tryPlayUci('b7b8'), isNotNull);

    final referee = Referee(fen);
    expect(referee.tryPlayUci('b7b8q'), isNull);
    expect(referee.sanHistory.last, contains('=Q'));
  });

  test('underpromotion is accepted', () {
    final referee = Referee('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1');
    expect(referee.tryPlayUci('b7b8n'), isNull);
  });

  test('castling', () {
    final referee = Referee(FenPosition.startingPosition);
    for (final uci in ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6']) {
      expect(referee.tryPlayUci(uci), isNull);
    }
    expect(referee.tryPlayUci('e1g1'), isNull);
    expect(referee.sanHistory.last, 'O-O');
  });

  test('en passant', () {
    final referee = Referee(FenPosition.startingPosition);
    for (final uci in ['e2e4', 'a7a6', 'e4e5', 'd7d5']) {
      expect(referee.tryPlayUci(uci), isNull);
    }
    expect(referee.tryPlayUci('e5d6'), isNull);
  });

  test('SAN play', () {
    final referee = Referee(FenPosition.startingPosition);
    expect(referee.tryPlaySan('Nf3'), isNull);
    expect(referee.uciHistory, ['g1f3']);
  });

  test("fool's mate", () {
    final referee = Referee(FenPosition.startingPosition);
    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      expect(referee.tryPlayUci(uci), isNull);
    }
    final end = referee.checkGameEnd();
    expect(end?.outcome, GameOutcome.blackWin);
    expect(end?.termination, GameTermination.checkmate);
  });

  test('stalemate', () {
    final referee = Referee('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
    final end = referee.checkGameEnd();
    expect(end?.outcome, GameOutcome.draw);
    expect(end?.termination, GameTermination.stalemate);
  });

  test('threefold repetition after the 8th ply, not before', () {
    final referee = Referee(FenPosition.startingPosition);
    const moves = ['g1f3', 'g8f6', 'f3g1', 'f6g8'];
    for (final uci in moves) {
      expect(referee.tryPlayUci(uci), isNull);
    }
    expect(referee.checkGameEnd(), isNull);

    for (final uci in moves) {
      expect(referee.tryPlayUci(uci), isNull);
    }
    final end = referee.checkGameEnd();
    expect(end?.outcome, GameOutcome.draw);
    expect(end?.termination, GameTermination.threefoldRepetition);
  });

  test('fifty-move rule', () {
    final referee = Referee('8/8/8/8/8/8/R7/K6k w - - 99 80');
    expect(referee.tryPlayUci('a2b2'), isNull);
    final end = referee.checkGameEnd();
    expect(end?.termination, GameTermination.fiftyMoveRule);
  });

  test('insufficient material', () {
    final referee = Referee('8/8/8/8/8/8/8/K6k w - - 0 1');
    final end = referee.checkGameEnd();
    expect(end?.outcome, GameOutcome.draw);
    expect(end?.termination, GameTermination.insufficientMaterial);
  });

  test('max plies', () {
    final referee = Referee(FenPosition.startingPosition, maxPlies: 4);
    for (final uci in ['g1f3', 'g8f6', 'f3g1', 'f6g8']) {
      expect(referee.tryPlayUci(uci), isNull);
    }
    final end = referee.checkGameEnd();
    expect(end?.termination, GameTermination.maxMoves);
  });

  test('a 4-field FEN constructs fine', () {
    final referee = Referee('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -');
    expect(referee.fen, endsWith('0 1'));
  });

  test('fen output tracks the clocks', () {
    final referee = Referee(FenPosition.startingPosition);
    expect(referee.tryPlayUci('e2e4'), isNull);
    expect(referee.fen, endsWith('b KQkq e3 0 1'));

    expect(referee.tryPlayUci('e7e5'), isNull);
    expect(referee.tryPlayUci('g1f3'), isNull);
    expect(referee.fen, endsWith('1 2'));
  });
}
