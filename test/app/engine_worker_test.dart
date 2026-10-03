import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:ace/services/engine_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v0 reports no stats', () async {
    final worker = await EngineWorker.spawn('v0');
    var count = 0;
    final sub = worker.stats.listen((_) => count++);
    final result = await worker.search(FenPosition.startingPosition, [], const Duration(milliseconds: 100));
    await sub.cancel();
    worker.dispose();
    expect(result.uciMove, isNotEmpty);
    expect(count, 0);
  });

  test('provider: human plays, engine replies, restart resets', () async {
    final game = GameProvider();
    await game.startGame(
      const GameSettings(engineId: 'v0', moveTime: Duration(milliseconds: 100), playerIsWhite: true),
    );
    expect(game.isHumanTurn, isTrue);

    final e2e4 = game.movesBetween(52, 36).single;
    game.playHumanMove(e2e4);
    expect(game.engineThinking, isTrue);

    while (game.engineThinking) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(game.isHumanTurn, isTrue);
    expect(game.stats, isNull); // v0 reports no stats

    await game.restart();
    expect(game.lastMove, isNull);
    expect(game.isHumanTurn, isTrue);
    game.endGame();
  });

  test('provider: engine moves first when player is black', () async {
    final game = GameProvider();
    await game.startGame(
      const GameSettings(engineId: 'v0', moveTime: Duration(milliseconds: 100), playerIsWhite: false),
    );
    expect(game.engineThinking, isTrue);
    while (game.engineThinking) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(game.lastMove, isNotNull);
    expect(game.isHumanTurn, isTrue);
    game.endGame();
  });
}
