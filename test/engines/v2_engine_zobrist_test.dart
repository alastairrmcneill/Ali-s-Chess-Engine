import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v2/core/board.dart';
import 'package:ace/engines/v2/v2_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// Deliberately no Zobrist() in setUpAll: V2Engine has to initialise the tables itself.
void main() {
  test('V2Engine initialises the zobrist tables, so positions get distinct keys', () {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final engine = V2Engine()..newGame();

    final result = engine.getMove(start, ['g1f3', 'g8f6'], SearchLimits(moveTime: const Duration(seconds: 1)));
    expect(result.uciMove, isNotEmpty);

    final a = Board.fromFEN(start);
    final b = Board.fromFEN('rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1');
    expect(a.zobristKey, isNot(0));
    expect(a.zobristKey, isNot(b.zobristKey));
  });
}
