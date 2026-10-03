import 'package:ace/chess_core/game_end.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v0/v0_engine.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/opening_book.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_engines.dart';

void main() {
  final limits = SearchLimits(moveTime: const Duration(milliseconds: 50));
  const noBook = Opening(0, []); // games below start from the standard position with no book moves

  test('plays the first opening book line to completion without an engine/illegal-move error', () async {
    final opening = OpeningBook.standard().openings[0];

    final record = await GameRunner().playGame(
      gameNumber: 1,
      opening: opening,
      white: V0Engine(),
      black: V0Engine(),
      engineAIsWhite: true,
      searchLimits: SearchLimits(moveTime: const Duration(milliseconds: 50)),
      maxPlies: 20,
    );
    print('Game record: ${record.toString()}');

    expect(record.uciMoves.sublist(0, record.bookPlies), opening.moves);
    expect(record.end.termination, isNot(GameTermination.illegalMove));
    expect(record.end.termination, isNot(GameTermination.engineError));
    expect(record.errorDetail, isNull);
  });

  test("scripted fool's mate ends in checkmate for Black", () async {
    final record = await GameRunner().playGame(
      gameNumber: 1,
      opening: noBook,
      white: ScriptedEngine(['f2f3', 'g2g4']),
      black: ScriptedEngine(['e7e5', 'd8h4']),
      engineAIsWhite: true,
      searchLimits: limits,
      maxPlies: 10,
    );

    expect(record.end.outcome, GameOutcome.blackWin);
    expect(record.end.termination, GameTermination.checkmate);
    expect(record.sanMoves, ['f3', 'e5', 'g4', 'Qh4#']);
  });

  test('an illegal move from White forfeits the game to Black', () async {
    final record = await GameRunner().playGame(
      gameNumber: 1,
      opening: noBook,
      white: IllegalEngine(),
      black: ScriptedEngine(['e7e5']),
      engineAIsWhite: true,
      searchLimits: limits,
      maxPlies: 10,
    );

    expect(record.end.outcome, GameOutcome.blackWin);
    expect(record.end.termination, GameTermination.illegalMove);
    expect(record.errorDetail, contains('a1a1'));
  });

  test('a crash from Black forfeits the game to White', () async {
    final record = await GameRunner().playGame(
      gameNumber: 1,
      opening: noBook,
      white: ScriptedEngine(['e2e4']),
      black: CrashingEngine(),
      engineAIsWhite: true,
      searchLimits: limits,
      maxPlies: 10,
    );

    expect(record.end.outcome, GameOutcome.whiteWin);
    expect(record.end.termination, GameTermination.engineError);
    expect(record.errorDetail, contains('boom'));
  });

  test('a malformed move string forfeits the game as an illegal move', () async {
    final record = await GameRunner().playGame(
      gameNumber: 1,
      opening: noBook,
      white: MalformedEngine(),
      black: ScriptedEngine(['e7e5']),
      engineAIsWhite: true,
      searchLimits: limits,
      maxPlies: 10,
    );

    expect(record.end.outcome, GameOutcome.blackWin);
    expect(record.end.termination, GameTermination.illegalMove);
  });

  test('an empty move string forfeits the game as an illegal move', () async {
    final record = await GameRunner().playGame(
      gameNumber: 1,
      opening: noBook,
      white: NoMoveEngine(),
      black: ScriptedEngine(['e7e5']),
      engineAIsWhite: true,
      searchLimits: limits,
      maxPlies: 10,
    );

    expect(record.end.outcome, GameOutcome.blackWin);
    expect(record.end.termination, GameTermination.illegalMove);
  });

  test('newGame() is called exactly once per engine per game', () async {
    final white = CountingEngine(ScriptedEngine(['f2f3', 'g2g4']));
    final black = CountingEngine(ScriptedEngine(['e7e5', 'd8h4']));

    await GameRunner().playGame(
      gameNumber: 1,
      opening: noBook,
      white: white,
      black: black,
      engineAIsWhite: true,
      searchLimits: limits,
      maxPlies: 10,
    );

    expect(white.newGameCalls, 1);
    expect(black.newGameCalls, 1);
    expect(white.getMoveCalls, 2);
    expect(black.getMoveCalls, 2);
  });
}
