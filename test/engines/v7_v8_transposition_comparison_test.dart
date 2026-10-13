import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class _Position {
  final String name;
  final String fen;
  final int depth;
  final String? mateMove; // when set, both engines must find this forced mate

  const _Position(this.name, this.fen, this.depth, {this.mateMove});
}

const _positions = [
  _Position('Dragon middlegame', 'r1bq1rk1/pp2ppbp/2np1np1/8/3NP3/2N1BP2/PPPQ2PP/R3KB1R w KQ - 0 9', 6),
  _Position('Kiwipete', 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', 5),
  _Position('Perft 3 (rook endgame)', '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', 7),
  _Position('Perft 4 (promotions)', 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', 5),
  _Position('Perft 5', 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', 5),
  _Position('Italian opening', 'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4', 6),
  _Position('Fine #70', '8/k7/3p4/p2P1p2/P2P1P2/8/8/K7 w - - 0 1', 9),
  _Position('King and pawn vs king', '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1', 10),
  _Position('Back rank mate in 1', '6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1', 4, mateMove: 'a1a8'),
  _Position('Forced mate (rook and bishop)', 'r5rk/5p1p/5R2/4B3/8/8/7P/7K w - - 0 1', 5),
];

class _Run {
  final String move;
  final int? eval;
  final int nodes;
  final int transpositions;
  final int ms;

  _Run(this.move, this.eval, this.nodes, this.transpositions, this.ms);
}

_Run _run(String engineId, _Position p) {
  final engine = EngineRegistry.create(engineId)..newGame();
  final stopwatch = Stopwatch()..start();
  final result = engine.getMove(p.fen, const [], SearchLimits(moveTime: const Duration(minutes: 5), depth: p.depth));
  stopwatch.stop();
  return _Run(
    result.uciMove,
    result.evaluation,
    result.stats?.nodes ?? result.nodes ?? 0,
    result.stats?.transpositions ?? 0,
    stopwatch.elapsedMilliseconds,
  );
}

String _pad(Object value, int width) => value.toString().padRight(width);

void main() {
  test('v7 vs v8 on transposition-heavy positions (fixed depth)', () {
    final lines = <String>[
      '${_pad('Position', 34)}${_pad('d', 3)}${_pad('v7 move', 8)}${_pad('v8 move', 8)}'
          '${_pad('v7 eval', 10)}${_pad('v8 eval', 10)}${_pad('v7 nodes', 11)}${_pad('v8 nodes', 11)}'
          '${_pad('TT hits', 10)}${_pad('v7 ms', 8)}${_pad('v8 ms', 8)}${_pad('nodes', 7)}',
    ];
    int v7Total = 0, v8Total = 0;

    for (final p in _positions) {
      final v7 = _run('v7', p);
      final v8 = _run('v8', p);
      v7Total += v7.nodes;
      v8Total += v8.nodes;

      expect(v7.move, isNotEmpty, reason: p.name);
      expect(v8.move, isNotEmpty, reason: p.name);
      if (p.mateMove != null) {
        expect(v7.move, p.mateMove, reason: 'v7 ${p.name}');
        expect(v8.move, p.mateMove, reason: 'v8 ${p.name}');
        expect(v8.eval, v7.eval, reason: '${p.name}: mate distance must match');
      }

      final ratio = v7.nodes == 0 ? 0 : 100 * v8.nodes / v7.nodes;
      lines.add('${_pad(p.name, 34)}${_pad(p.depth, 3)}${_pad(v7.move, 8)}${_pad(v8.move, 8)}'
          '${_pad(v7.eval ?? '-', 10)}${_pad(v8.eval ?? '-', 10)}${_pad(v7.nodes, 11)}${_pad(v8.nodes, 11)}'
          '${_pad(v8.transpositions, 10)}${_pad(v7.ms, 8)}${_pad(v8.ms, 8)}${ratio.toStringAsFixed(0)}%');
    }

    lines.add('Total nodes: v7 $v7Total, v8 $v8Total (${(100 * v8Total / v7Total).toStringAsFixed(0)}% of v7)');
    // ignore: avoid_print
    print(lines.join('\n'));

    expect(v8Total, lessThan(v7Total), reason: 'the table should reduce total nodes searched');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
