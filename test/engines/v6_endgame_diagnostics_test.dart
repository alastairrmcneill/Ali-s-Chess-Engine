// Diagnostics for v6 mop-up / KRK problems. Prints a lot; run with:
//   flutter test test/engines/v6_endgame_diagnostics_test.dart
// Fixed depth instead of the 1s timer (separates eval bugs from speed bugs):
//   DEPTH=8 flutter test test/engines/v6_endgame_diagnostics_test.dart
// Different time per move: MOVE_MS=3000
// Only one group: --plain-name "gradient" / "sign" / "self-play"
import 'dart:io';

import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v6/core/board.dart';
import 'package:ace/engines/v6/core/move_generator.dart';
import 'package:ace/engines/v6/core/zobrist.dart';
import 'package:ace/engines/v6/search/evaluator.dart';
import 'package:ace/engines/v6/v6_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _krkWhiteStrong = '8/8/8/4k3/8/8/4K3/R7 w - - 0 1';
const _krkBlackStrong = 'r7/4k3/8/8/4K3/8/8/8 b - - 0 1';
const _krkWeakKingToMove = '8/8/8/4k3/8/8/4K3/R7 b - - 0 1';
const _krrk = '8/8/8/4k3/8/8/R3K3/R7 w - - 0 1';

int _eval(String fen) {
  Zobrist.ensureInitialised();
  return Evaluator().evaluate(Board.fromFEN(fen));
}

SearchLimits _limits() {
  final depth = int.tryParse(Platform.environment['DEPTH'] ?? '');
  final ms = int.tryParse(Platform.environment['MOVE_MS'] ?? '') ?? 1000;
  return SearchLimits(moveTime: Duration(milliseconds: ms), depth: depth);
}

/// Plays the engine against itself and prints one line per ply. Returns the result string.
String _selfPlay(String name, String startFen, {int maxPlies = 120}) {
  Zobrist.ensureInitialised();
  final engine = V6Engine()..newGame();
  final board = Board.fromFEN(startFen);
  final generator = MoveGenerator();
  final uciMoves = <String>[];
  final seen = <int, int>{board.zobristKey: 1};
  final limits = _limits();

  print('\n=== self-play: $name ($startFen) limits: depth=${limits.depth} time=${limits.moveTime} ===');
  print('ply side move   eval(white)  depth  nodes   notes');

  for (var ply = 0; ply < maxPlies; ply++) {
    final legal = generator.generateLegalMoves(board);
    if (legal.isEmpty) {
      final result = generator.inCheck ? 'CHECKMATE (${board.whiteToPlay ? "black" : "white"} wins)' : 'STALEMATE';
      print('--> $result after $ply plies');
      return result;
    }
    if (board.fiftyMoveRule >= 100) {
      print('--> DRAW 50-move after $ply plies');
      return '50-move';
    }
    final pieces = board.position.where((p) => p != 0).length;
    if (pieces == 2) {
      print('--> rook lost, bare kings after $ply plies');
      return 'rook lost';
    }

    final whiteMoving = board.whiteToPlay;
    final result = engine.getMove(startFen, uciMoves, limits);
    // EngineMoveResult.evaluation is already from white's view in v6_engine.dart.
    final notes = StringBuffer();
    if (result.stats != null && result.stats!.aborted) notes.write('aborted ');

    print('${ply.toString().padLeft(3)} ${whiteMoving ? "W" : "B"}    ${result.uciMove.padRight(6)} '
        '${result.evaluation.toString().padLeft(11)}  ${result.depth.toString().padLeft(5)}  '
        '${result.nodes.toString().padLeft(7)}  $notes');

    final move = legal.firstWhere((m) => m.uci == result.uciMove);
    board.makeMove(move);
    uciMoves.add(result.uciMove);

    final count = (seen[board.zobristKey] ?? 0) + 1;
    seen[board.zobristKey] = count;
    if (count >= 3) {
      print('--> DRAW threefold after ${ply + 1} plies');
      return 'threefold';
    }
  }
  print('--> NO RESULT after $maxPlies plies');
  return 'no result';
}

void main() {
  group('sign', () {
    // Same KRK position seen from both sides. evaluate() is from the side to move's view.
    test('KRK, strong side to move vs weak side to move', () {
      final strongToMove = _eval(_krkWhiteStrong);
      final weakToMove = _eval(_krkWeakKingToMove);
      print('white strong, white to move : $strongToMove  (expect large +, ~500 + mop-up)');
      print('white strong, black to move : $weakToMove  (expect the same magnitude, negative)');
      expect(strongToMove, greaterThan(400), reason: 'material missing from mop-up path or sign wrong');
      expect(weakToMove, lessThan(-400));
      expect(strongToMove, -weakToMove);
    });

    test('colour mirror: black strong scores like white strong', () {
      final white = _eval(_krkWhiteStrong);
      final black = _eval(_krkBlackStrong);
      print('white strong (white to move): $white');
      print('black strong (black to move): $black');
      expect(black, greaterThan(400));
    });

    test('KRK scores continuously with the non-mop-up eval', () {
      // Weak side has a pawn, so mop-up is off and plain material is used.
      final plain = _eval('8/8/8/4k3/8/8/4K2p/R7 w - - 0 1');
      final bare = _eval(_krkWhiteStrong);
      print('R vs P (no mop-up): $plain   R vs bare king (mop-up): $bare');
      // A bare-king win must never be worth less than the same material without mop-up.
      expect(bare, greaterThanOrEqualTo(500), reason: 'cliff: mop-up score fell below plain material');
    });

    test('insufficient material is a draw', () {
      for (final fen in [
        '8/8/8/4k3/8/8/4K3/N7 w - - 0 1',
        '8/8/8/4k3/8/8/4K3/B7 w - - 0 1',
        '8/8/8/4k3/8/8/4K3/8 w - - 0 1',
      ]) {
        final e = _eval(fen);
        print('$fen -> $e (expect 0)');
        expect(e, 0);
      }
    });
  });

  group('gradient', () {
    // White rook + king vs black king, white to move. Score should RISE down this list.
    // Rook on a1 (far from the black king) in all of them.
    final ladder = <String, String>{
      'weak K centre,  strong K far ': '8/8/8/3k4/8/8/7K/R7 w - - 0 1',
      'weak K centre,  strong K near': '8/8/8/3k4/3K4/8/8/R7 w - - 0 1',
      'weak K edge,    strong K far ': '8/8/8/7k/8/8/K7/R7 w - - 0 1',
      'weak K edge,    strong K near': '8/8/8/7k/5K2/8/8/R7 w - - 0 1',
      'weak K corner,  strong K far ': '7k/8/8/8/8/8/K7/R7 w - - 0 1',
      'weak K corner,  strong K near': '7k/8/5K2/8/8/8/8/R7 w - - 0 1',
    };

    test('mop-up gradient pushes weak king to edge, strong king close', () {
      int? previous;
      ladder.forEach((label, fen) {
        final e = _eval(fen);
        print('${label.padRight(30)} $e');
        previous = e;
      });
      expect(previous, isNotNull);

      expect(_eval(ladder['weak K edge,    strong K far ']!), greaterThan(_eval(ladder['weak K centre,  strong K far ']!)),
          reason: 'edge should score higher than centre (centre-distance term backwards?)');
      expect(_eval(ladder['weak K corner,  strong K far ']!), greaterThan(_eval(ladder['weak K edge,    strong K far ']!)));
      expect(_eval(ladder['weak K centre,  strong K near']!), greaterThan(_eval(ladder['weak K centre,  strong K far ']!)),
          reason: 'closer strong king should score higher');
    });
  });

  group('self-play', () {
    test('KRK, white strong', () {
      final result = _selfPlay('KRK white strong', _krkWhiteStrong);
      print('RESULT: $result');
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('KRK, black strong', () {
      final result = _selfPlay('KRK black strong', _krkBlackStrong);
      print('RESULT: $result');
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('KRRK control (should mate)', () {
      final result = _selfPlay('KRRK', _krrk);
      print('RESULT: $result');
    }, timeout: const Timeout(Duration(minutes: 15)));
  });
}
