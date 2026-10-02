import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:flutter_test/flutter_test.dart';

int _sq(String name) => BoardHelper.squareIndex(name);

void main() {
  test('player moves, then the selected engine replies', () async {
    final provider = GameProvider()..thinkingTime = 20;
    expect(provider.engineIds, contains('v1'));

    await provider.select(_sq('e2'));
    expect(provider.legalTargetsFrom(_sq('e2')), unorderedEquals([_sq('e3'), _sq('e4')]));
    await provider.select(_sq('e4'));

    expect(provider.pieceAt(_sq('e4')), Piece.white | Piece.pawn);
    expect(provider.whiteToPlay, isTrue, reason: 'the engine should have replied as Black');
    expect(provider.engineProblem, isNull);
    expect(provider.lastMove, isNotNull);
  });

  test("can't select the opponent's pieces", () async {
    final provider = GameProvider();
    await provider.select(_sq('e7'));
    expect(provider.selectedIndex, isNull);
  });

  test('changing the engine version starts a new game', () async {
    final provider = GameProvider()..thinkingTime = 20;
    await provider.select(_sq('e2'));
    await provider.select(_sq('e4'));
    provider.setEngine(provider.engineIds.first);
    provider.setEngine('random'); // test engine: not in the picker, but setEngine accepts any registered id
    expect(provider.pieceAt(_sq('e2')), Piece.white | Piece.pawn);
    expect(provider.lastMove, isNull);
  });
}
