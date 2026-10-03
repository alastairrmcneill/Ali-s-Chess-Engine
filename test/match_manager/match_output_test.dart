import 'package:ace/match_manager/match_output.dart';
import 'package:ace/match_manager/match_config.dart';
import 'package:ace/match_manager/match_stats.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/chess_core/game_end.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('MatchOutput.create', () {
    test('creates a directory with timestamp and engine IDs', () {
      final config = MatchConfig(
        engineAId: 'v1',
        engineBId: 'v2',
      );
      final output = MatchOutput.create(
        config,
        engineAName: 'Engine V1',
        engineBName: 'Engine V2',
      );

      expect(output.directory.path, contains('match_results'));
      expect(output.directory.path, contains('v1-vs-v2'));
      expect(output.config, config);
    });

    test('creates directories for different engine pairs', () {
      final config1 = MatchConfig(engineAId: 'alpha', engineBId: 'beta');
      final config2 = MatchConfig(engineAId: 'gamma', engineBId: 'delta');

      final output1 = MatchOutput.create(config1, engineAName: 'A', engineBName: 'B');
      final output2 = MatchOutput.create(config2, engineAName: 'C', engineBName: 'D');

      expect(output1.directory.path, contains('alpha-vs-beta'));
      expect(output2.directory.path, contains('gamma-vs-delta'));
    });

    test('event name matches engine display names', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(
        config,
        engineAName: 'My Engine A',
        engineBName: 'My Engine B',
      );
      expect(output.event, contains('My Engine A'));
      expect(output.event, contains('My Engine B'));
    });
  });

  group('MatchOutput file paths', () {
    test('creates expected file paths in directory', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(config, engineAName: 'A', engineBName: 'B');

      // Check that directory exists with expected structure
      expect(output.directory.existsSync(), true);
      expect(output.directory.path, contains('match_results'));

      // Test file paths by creating them
      final pgnFile = File('${output.directory.path}/games.pgn');
      final errorsFile = File('${output.directory.path}/errors.log');

      // Files should have correct names and paths
      expect(pgnFile.path, contains('games.pgn'));
      expect(errorsFile.path, contains('errors.log'));

      output.directory.deleteSync(recursive: true);
    });
  });

  group('MatchOutput.writeConfig', () {
    test('creates config.txt file with match details', () {
      final config = MatchConfig(
        engineAId: 'v1',
        engineBId: 'v2',
        games: 100,
        moveTime: Duration(milliseconds: 500),
        maxMoves: 200,
      );
      final output = MatchOutput.create(config, engineAName: 'V1', engineBName: 'V2');

      output.writeConfig(openingCount: 500, warnings: []);

      final file = File('${output.directory.path}/config.txt');
      expect(file.existsSync(), true);

      final content = file.readAsStringSync();
      expect(content, contains('engine A:   v1'));
      expect(content, contains('engine B:   v2'));
      expect(content, contains('games:      100'));
      expect(content, contains('movetime:   500 ms'));
      expect(content, contains('max moves:  200 per side'));
      expect(content, contains('openings:   500'));

      // Cleanup
      file.deleteSync();
    });

    test('includes warnings in config.txt when present', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(config, engineAName: 'V1', engineBName: 'V2');

      final warnings = ['Warning 1', 'Warning 2', 'Warning 3'];
      output.writeConfig(openingCount: 500, warnings: warnings);

      final file = File('${output.directory.path}/config.txt');
      final content = file.readAsStringSync();

      expect(content, contains('warnings:'));
      expect(content, contains('Warning 1'));
      expect(content, contains('Warning 2'));
      expect(content, contains('Warning 3'));

      file.deleteSync();
    });

    test('omits warnings section when empty', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(config, engineAName: 'V1', engineBName: 'V2');

      output.writeConfig(openingCount: 500, warnings: []);

      final file = File('${output.directory.path}/config.txt');
      final content = file.readAsStringSync();

      expect(content, isNot(contains('warnings:')));

      file.deleteSync();
    });

    test('includes timestamp', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(config, engineAName: 'V1', engineBName: 'V2');

      output.writeConfig(openingCount: 500, warnings: []);

      final file = File('${output.directory.path}/config.txt');
      final content = file.readAsStringSync();

      expect(content, contains('started:'));

      file.deleteSync();
    });
  });

  group('MatchOutput.addGame', () {
    test('appends game to pgn file', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(config, engineAName: 'V1', engineBName: 'V2');

      final record = GameRecord(
        gameNumber: 1,
        openingIndex: 0,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 0,
        whiteId: 'v1',
        blackId: 'v2',
        whiteName: 'V1',
        blackName: 'V2',
        engineAIsWhite: true,
        end: GameEnd(outcome: GameOutcome.whiteWin, termination: GameTermination.checkmate),
        uciMoves: [],
        sanMoves: [],
        moveStats: [],
        duration: Duration(seconds: 1),
      );

      output.addGame(record);

      final file = File('${output.directory.path}/games.pgn');
      expect(file.existsSync(), true);

      final content = file.readAsStringSync();
      expect(content, isNotEmpty);

      file.deleteSync();
    });

    test('does not log games without errors to errors.log', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(config, engineAName: 'V1', engineBName: 'V2');

      final record = GameRecord(
        gameNumber: 1,
        openingIndex: 0,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 0,
        whiteId: 'v1',
        blackId: 'v2',
        whiteName: 'V1',
        blackName: 'V2',
        engineAIsWhite: true,
        end: GameEnd(outcome: GameOutcome.whiteWin, termination: GameTermination.checkmate),
        uciMoves: [],
        sanMoves: [],
        moveStats: [],
        duration: Duration(seconds: 1),
      );

      output.addGame(record);

      final file = File('${output.directory.path}/errors.log');
      expect(file.existsSync(), false);

      File('${output.directory.path}/games.pgn').deleteSync();
    });

    test('logs forfeits to errors.log', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(config, engineAName: 'V1', engineBName: 'V2');

      final record = GameRecord(
        gameNumber: 1,
        openingIndex: 0,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        bookPlies: 0,
        whiteId: 'v1',
        blackId: 'v2',
        whiteName: 'V1',
        blackName: 'V2',
        engineAIsWhite: true,
        end: GameEnd(
          outcome: GameOutcome.blackWin,
          termination: GameTermination.illegalMove,
          detail: 'White played illegal move',
        ),
        uciMoves: [],
        sanMoves: [],
        moveStats: [],
        errorDetail: 'Stack trace info',
        duration: Duration(seconds: 1),
      );

      output.addGame(record);

      final file = File('${output.directory.path}/errors.log');
      expect(file.existsSync(), true);

      final content = file.readAsStringSync();
      expect(content, contains('Game 1'));
      expect(content, contains('illegalMove'));

      file.deleteSync();
      File('${output.directory.path}/games.pgn').deleteSync();
    });
  });

  group('MatchOutput directory management', () {
    test('creates nested directories', () {
      final config = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final output = MatchOutput.create(config, engineAName: 'V1', engineBName: 'V2');

      expect(output.directory.existsSync(), true);

      output.directory.deleteSync(recursive: true);
    });

    test('handles multiple matches with different engine IDs', () {
      final config1 = MatchConfig(engineAId: 'v1', engineBId: 'v2');
      final config2 = MatchConfig(engineAId: 'v1', engineBId: 'v3');

      final output1 = MatchOutput.create(config1, engineAName: 'V1', engineBName: 'V2');
      final output2 = MatchOutput.create(config2, engineAName: 'V1', engineBName: 'V3');

      expect(output1.directory.path, contains('v1-vs-v2'));
      expect(output2.directory.path, contains('v1-vs-v3'));

      output1.directory.deleteSync(recursive: true);
      output2.directory.deleteSync(recursive: true);
    });
  });
}
