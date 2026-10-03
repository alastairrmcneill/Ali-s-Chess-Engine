import 'package:ace/match_manager/match_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchConfig', () {
    test('creates with required engine IDs', () {
      const config = MatchConfig(
        engineAId: 'v1',
        engineBId: 'v2',
      );
      expect(config.engineAId, 'v1');
      expect(config.engineBId, 'v2');
    });

    test('uses default values when not provided', () {
      const config = MatchConfig(
        engineAId: 'v1',
        engineBId: 'v2',
      );
      expect(config.games, 1000);
      expect(config.moveTime, const Duration(milliseconds: 100));
      expect(config.maxMoves, 300);
    });

    test('can override default games', () {
      const config = MatchConfig(
        engineAId: 'v1',
        engineBId: 'v2',
        games: 100,
      );
      expect(config.games, 100);
    });

    test('can override default moveTime', () {
      const config = MatchConfig(
        engineAId: 'v1',
        engineBId: 'v2',
        moveTime: const Duration(milliseconds: 500),
      );
      expect(config.moveTime, const Duration(milliseconds: 500));
    });

    test('can override default maxMoves', () {
      const config = MatchConfig(
        engineAId: 'v1',
        engineBId: 'v2',
        maxMoves: 150,
      );
      expect(config.maxMoves, 150);
    });

    test('can override all values', () {
      const config = MatchConfig(
        engineAId: 'engineA',
        engineBId: 'engineB',
        games: 50,
        moveTime: const Duration(milliseconds: 1000),
        maxMoves: 200,
      );
      expect(config.engineAId, 'engineA');
      expect(config.engineBId, 'engineB');
      expect(config.games, 50);
      expect(config.moveTime, const Duration(milliseconds: 1000));
      expect(config.maxMoves, 200);
    });

    group('maxPlies calculation', () {
      test('maxPlies is exactly maxMoves * 2', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          maxMoves: 300,
        );
        expect(config.maxPlies, 600);
      });

      test('maxPlies updates with custom maxMoves', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          maxMoves: 150,
        );
        expect(config.maxPlies, 300);
      });

      test('maxPlies for small maxMoves', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          maxMoves: 1,
        );
        expect(config.maxPlies, 2);
      });

      test('maxPlies for large maxMoves', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          maxMoves: 1000,
        );
        expect(config.maxPlies, 2000);
      });
    });

    group('engine IDs', () {
      test('stores different engine combinations', () {
        const config1 = MatchConfig(engineAId: 'v1', engineBId: 'v2');
        const config2 = MatchConfig(engineAId: 'v2', engineBId: 'v3');
        expect(config1.engineAId, 'v1');
        expect(config1.engineBId, 'v2');
        expect(config2.engineAId, 'v2');
        expect(config2.engineBId, 'v3');
      });

      test('engine IDs can be the same (self-play)', () {
        const config = MatchConfig(engineAId: 'v1', engineBId: 'v1');
        expect(config.engineAId, 'v1');
        expect(config.engineBId, 'v1');
      });
    });

    group('games configuration', () {
      test('supports very small number of games', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          games: 1,
        );
        expect(config.games, 1);
      });

      test('supports large number of games', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          games: 10000,
        );
        expect(config.games, 10000);
      });

      test('supports even number of games', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          games: 1000,
        );
        expect(config.games, 1000);
        expect(config.games % 2, 0);
      });

      test('supports odd number of games', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          games: 999,
        );
        expect(config.games, 999);
        expect(config.games % 2, 1);
      });
    });

    group('move time configuration', () {
      test('supports millisecond precision', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          moveTime: const Duration(milliseconds: 50),
        );
        expect(config.moveTime.inMilliseconds, 50);
      });

      test('supports second-based duration', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          moveTime: const Duration(seconds: 1),
        );
        expect(config.moveTime.inMilliseconds, 1000);
      });

      test('supports long time controls', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          moveTime: const Duration(seconds: 60),
        );
        expect(config.moveTime.inMilliseconds, 60000);
      });

      test('supports very fast blitz', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          moveTime: const Duration(milliseconds: 10),
        );
        expect(config.moveTime.inMilliseconds, 10);
      });
    });

    group('const constructor', () {
      test('is a const constructor', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
        );
        expect(config.engineAId, 'v1');
        expect(config.engineBId, 'v2');
      });

      test('two identical configs are equal', () {
        const config1 = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
        );
        const config2 = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
        );
        // Note: Dart const equality for non-identical classes
        expect(config1.engineAId, config2.engineAId);
        expect(config1.engineBId, config2.engineBId);
      });
    });

    group('real-world configs', () {
      test('quick blitz match config', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          games: 100,
          moveTime: const Duration(milliseconds: 50),
          maxMoves: 300,
        );
        expect(config.games, 100);
        expect(config.moveTime.inMilliseconds, 50);
        expect(config.maxPlies, 600);
      });

      test('long classical match config', () {
        const config = MatchConfig(
          engineAId: 'v1',
          engineBId: 'v2',
          games: 10,
          moveTime: const Duration(seconds: 60),
          maxMoves: 500,
        );
        expect(config.games, 10);
        expect(config.moveTime.inMilliseconds, 60000);
        expect(config.maxPlies, 1000);
      });

      test('self-play config', () {
        const config = MatchConfig(
          engineAId: 'v2',
          engineBId: 'v2',
          games: 1000,
          moveTime: const Duration(milliseconds: 200),
          maxMoves: 300,
        );
        expect(config.engineAId, config.engineBId);
        expect(config.games, 1000);
      });
    });
  });
}
