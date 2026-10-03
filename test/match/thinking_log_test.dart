import 'dart:convert';

import 'package:ace/chess_core/game_end.dart';
import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/opening_book.dart';
import 'package:ace/match/thinking_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2 games produce valid JSONL with move, pv, depth and nodes', () async {
    final record = await GameRunner().playGame(
      gameNumber: 7,
      opening: const Opening(0, ['e2e4', 'e7e5']),
      white: EngineRegistry.create('v2'),
      black: EngineRegistry.create('v1'),
      engineAIsWhite: true,
      searchLimits: SearchLimits(moveTime: const Duration(milliseconds: 40)),
      maxPlies: 3,
    );

    final lines = ThinkingLog.linesForGame(record);
    expect(lines, hasLength(record.moveStats.length));
    expect(lines, isNotEmpty);

    for (var i = 0; i < lines.length; i++) {
      final json = jsonDecode(lines[i]) as Map<String, dynamic>;
      final stat = record.moveStats[i];
      expect(json['game'], 7);
      expect(json['ply'], record.bookPlies + i + 1);
      expect(json['side'], record.engineMoveIsWhite(i) ? 'white' : 'black');
      expect(json['move'], record.uciMoves[record.bookPlies + i]);
      expect(json['depth'], stat.depth);
      expect(json['nodes'], stat.nodes);
      expect(json.keys, unorderedEquals(['game', 'ply', 'side', 'move', 'pv', 'depth', 'nodes']));
      expect((json['pv'] as List).first, json['move']);
    }
  });

  test('engines without a pv write nothing', () {
    final record = GameRecord(
      gameNumber: 1,
      openingIndex: 0,
      startFen: FenPosition.startingPosition,
      bookPlies: 0,
      whiteId: 'a',
      blackId: 'b',
      whiteName: 'A',
      blackName: 'B',
      engineAIsWhite: true,
      end: GameEnd(outcome: GameOutcome.draw, termination: GameTermination.maxMoves),
      uciMoves: const ['e2e4'],
      sanMoves: const ['e4'],
      moveStats: const [MoveStat(10, null, null, null)],
      duration: Duration.zero,
    );
    expect(ThinkingLog.linesForGame(record), isEmpty);
  });
}
