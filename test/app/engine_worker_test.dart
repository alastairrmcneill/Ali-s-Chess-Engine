import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:ace/services/engine_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worker streams one event per iterative deepening step from v2 and returns a move', () async {
    final worker = await EngineWorker.spawn('v2');
    final stats = <SearchStats>[];
    final sub = worker.stats.listen(stats.add);

    final result = await worker.search(FenPosition.startingPosition, [], const Duration(milliseconds: 600));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    worker.dispose();

    expect(result.uciMove, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
    expect(stats.length, greaterThan(2), reason: 'expected one event per iteration');
    expect(stats.map((s) => s.depth).toList(), orderedEquals([for (var d = 1; d <= stats.length; d++) d]));
    expect(stats.last.nodes + stats.last.qNodes, greaterThan(0));
    expect(stats.first.pv, isNotEmpty);
    expect(result.principalVariation!.first, result.uciMove);
    expect(result.depth, greaterThan(0));
  });

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
      const GameSettings(engineId: 'v1', moveTime: Duration(milliseconds: 100), playerIsWhite: true),
    );
    expect(game.isHumanTurn, isTrue);

    final e2e4 = game.movesBetween(52, 36).single;
    game.playHumanMove(e2e4);
    expect(game.engineThinking, isTrue);

    while (game.engineThinking) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(game.isHumanTurn, isTrue);
    expect(game.stats, isNotNull);

    await game.restart();
    expect(game.lastMove, isNull);
    expect(game.isHumanTurn, isTrue);
    game.endGame();
  });

  test('provider: engine moves first when player is black', () async {
    final game = GameProvider();
    await game.startGame(
      const GameSettings(engineId: 'v2', moveTime: Duration(milliseconds: 100), playerIsWhite: false),
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
