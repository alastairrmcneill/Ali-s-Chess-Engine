import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/referee.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = Referee.standardStartFen;

Referee _play(List<String> moves, {String? fen, int maxPlies = 600}) {
  final referee = Referee(fen ?? _start, maxPlies: maxPlies);
  for (final move in moves) {
    expect(referee.tryPlayUci(move), isNull, reason: 'expected $move to be legal');
  }
  return referee;
}

void main() {
  test('legal move', () {
    final referee = _play(['e2e4']);
    expect(referee.uciHistory, ['e2e4']);
    expect(referee.sanHistory, ['e4']);
    expect(referee.whiteToMove, isFalse);
  });

  test('illegal move is rejected and history unchanged', () {
    final referee = Referee(_start);
    expect(referee.tryPlayUci('e2e5'), isNotNull);
    expect(referee.uciHistory, isEmpty);
  });

  test('malformed moves are rejected', () {
    final referee = Referee(_start);
    for (final bad in ['E2E4', 'e2', 'e7e8k', 'e2e4 ', '']) {
      expect(referee.tryPlayUci(bad), isNotNull, reason: bad);
    }
  });

  test('promotion must name the piece', () {
    const fen = '4k3/1P6/8/8/8/8/8/4K3 w - - 0 1';
    expect(Referee(fen).tryPlayUci('b7b8'), isNotNull);
    final queen = _play(['b7b8q'], fen: fen);
    expect(queen.sanHistory.single, contains('=Q'));
    expect(_play(['b7b8n'], fen: fen).sanHistory.single, 'b8=N');
  });

  test('castling and en passant', () {
    expect(_play(['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'e1g1']).sanHistory.last, 'O-O');
    expect(_play(['e2e4', 'a7a6', 'e4e5', 'd7d5', 'e5d6']).sanHistory.last, 'exd6');
  });

  test('SAN moves', () {
    final referee = Referee(_start);
    expect(referee.tryPlaySan('Nf3'), isNull);
    expect(referee.uciHistory, ['g1f3']);
    expect(referee.tryPlaySan('Nf3'), isNotNull);
  });

  test('checkmate', () {
    final end = _play(['f2f3', 'e7e5', 'g2g4', 'd8h4']).checkGameEnd();
    expect(end?.outcome, GameOutcome.blackWin);
    expect(end?.termination, GameTermination.checkmate);
    expect(end?.pgnResult, '0-1');
  });

  test('stalemate', () {
    final end = Referee('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1').checkGameEnd();
    expect(end?.outcome, GameOutcome.draw);
    expect(end?.termination, GameTermination.stalemate);
  });

  test('threefold repetition after the 8th ply, not before', () {
    final shuffle = ['g1f3', 'g8f6', 'f3g1', 'f6g8'];
    final referee = _play([...shuffle, ...shuffle.sublist(0, 3)]);
    expect(referee.checkGameEnd(), isNull);
    referee.tryPlayUci(shuffle[3]);
    expect(referee.checkGameEnd()?.termination, GameTermination.threefoldRepetition);
  });

  test('fifty-move rule', () {
    final referee = _play(['a2b2'], fen: '8/8/8/8/8/8/R7/K6k w - - 99 80');
    expect(referee.checkGameEnd()?.termination, GameTermination.fiftyMoveRule);
  });

  test('insufficient material', () {
    expect(Referee('8/8/8/8/8/8/8/K6k w - - 0 1').checkGameEnd()?.termination, GameTermination.insufficientMaterial);
    expect(Referee('8/8/8/8/8/8/8/KN5k w - - 0 1').checkGameEnd()?.termination, GameTermination.insufficientMaterial);
    // Same-coloured bishops (c1 and f8 are both dark squares)
    expect(Referee('5b1k/8/8/8/8/8/8/K1B5 w - - 0 1').checkGameEnd()?.termination,
        GameTermination.insufficientMaterial);
    // Opposite-coloured bishops can still mate (in theory)
    expect(Referee('4b2k/8/8/8/8/8/8/K1B5 w - - 0 1').checkGameEnd(), isNull);
    expect(Referee('8/8/8/8/8/8/8/KR5k w - - 0 1').checkGameEnd(), isNull);
  });

  test('max plies', () {
    final referee = _play(['g1f3', 'g8f6', 'f3g1', 'f6g8'], maxPlies: 4);
    expect(referee.checkGameEnd()?.termination, GameTermination.maxMoves);
  });

  test('4-field FEN', () {
    expect(Referee('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -').legalUciMoves(), hasLength(20));
  });

  test('history lists cannot be modified from outside', () {
    final referee = _play(['e2e4']);
    expect(() => referee.uciHistory.add('e7e5'), throwsUnsupportedError);
  });
}
