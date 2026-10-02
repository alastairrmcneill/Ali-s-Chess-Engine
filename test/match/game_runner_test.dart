import 'package:ace/chess_core/game_end.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/random/random_engine.dart';
import 'package:ace/engines/v1/v1_engine.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/opening_book.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_engines.dart';

const _limits = SearchLimits(moveTime: Duration(milliseconds: 20));
const _noBook = Opening(0, []);

Future<GameRecord> _play(ChessEngine white, ChessEngine black, {Opening opening = _noBook, int maxEnginePlies = 600}) {
  return GameRunner.playGame(
    gameNumber: 1,
    opening: opening,
    white: white,
    black: black,
    engineAIsWhite: true,
    limits: _limits,
    maxEnginePlies: maxEnginePlies,
  );
}

void main() {
  test("scripted fool's mate", () async {
    final record = await _play(ScriptedEngine(['f2f3', 'g2g4']), ScriptedEngine(['e7e5', 'd8h4']));
    expect(record.end.outcome, GameOutcome.blackWin);
    expect(record.end.termination, GameTermination.checkmate);
    expect(record.sanMoves, ['f3', 'e5', 'g4', 'Qh4#']);
    expect(record.moveStats, hasLength(4));
  });

  test('book moves are played first and not counted as engine moves', () async {
    const opening = Opening(7, ['f2f3', 'e7e5']);
    final record = await _play(ScriptedEngine(['g2g4']), ScriptedEngine(['d8h4']), opening: opening);
    expect(record.uciMoves, ['f2f3', 'e7e5', 'g2g4', 'd8h4']);
    expect(record.bookPlies, 2);
    expect(record.openingIndex, 7);
    expect(record.moveStats, hasLength(2));
    expect(record.engineMoveIsWhite(0), isTrue);
    expect(record.engineMoveIsWhite(1), isFalse);
  });

  test('illegal move loses', () async {
    final record = await _play(IllegalEngine(), RandomEngine(seed: 1));
    expect(record.end.outcome, GameOutcome.blackWin);
    expect(record.end.termination, GameTermination.illegalMove);
    expect(record.end.detail, contains('e2e5'));
  });

  test('a crash loses, with the stack trace recorded', () async {
    final record = await _play(ScriptedEngine(['e2e4']), CrashingEngine());
    expect(record.end.outcome, GameOutcome.whiteWin);
    expect(record.end.termination, GameTermination.engineError);
    expect(record.errorDetail, contains('boom'));
  });

  test('malformed and empty moves lose', () async {
    expect((await _play(MalformedEngine(), RandomEngine())).end.termination, GameTermination.illegalMove);
    expect((await _play(NoMoveEngine(), RandomEngine())).end.termination, GameTermination.illegalMove);
  });

  test("an engine can't change the referee's history", () async {
    final record = await _play(TamperingEngine(), RandomEngine(seed: 3), maxEnginePlies: 1);
    expect(record.end.termination, GameTermination.engineError);
  });

  test('max engine plies ends in a draw', () async {
    final record = await _play(RandomEngine(seed: 1), RandomEngine(seed: 2), maxEnginePlies: 20);
    expect(record.moveStats.length, lessThanOrEqualTo(20));
    if (record.moveStats.length == 20) expect(record.end.termination, GameTermination.maxMoves);
  });

  test('newGame is called once per engine per game', () async {
    final white = ScriptedEngine(['f2f3', 'g2g4']), black = ScriptedEngine(['e7e5', 'd8h4']);
    await _play(white, black);
    expect(white.newGameCalls, 1);
    expect(black.newGameCalls, 1);
  });

  test('v1 can play a whole game against random', () async {
    final record = await _play(V1Engine(), RandomEngine(seed: 5), maxEnginePlies: 60);
    expect(record.end.termination, isNot(GameTermination.illegalMove));
    expect(record.end.termination, isNot(GameTermination.engineError));
    expect(record.moveStats, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
