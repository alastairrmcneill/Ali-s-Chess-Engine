import 'package:ace/chess_core/game_end.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v1/v1_engine.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/opening_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plays the first opening book line to completion without an engine/illegal-move error', () async {
    final opening = OpeningBook.standard().openings[0];

    final record = await GameRunner().playGame(
      gameNumber: 1,
      opening: opening,
      white: V1Engine(),
      black: V1Engine(),
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
}
