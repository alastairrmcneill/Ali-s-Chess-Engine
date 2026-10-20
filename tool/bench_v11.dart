// v11 benchmark. Run: dart run tool/bench_v11.dart [--depth N] [--perft] [--only <substring>]
//
// Fixed-depth search over a small FEN suite, so node counts are comparable between versions of the code.
//   - Pure speed-ups (same search): best moves AND node counts must not change, nps should go up.
//   - Search changes (pruning, ordering): node counts change on purpose; check time-to-depth and best moves.
// --perft also runs perft on a few positions, checks the known counts, and reports movegen speed.
//
// Record the totals line in docs/v11_speedups.md (Results log). Run in AOT for steady numbers:
//   dart compile exe tool/bench_v11.dart -o /tmp/bench_v11 && /tmp/bench_v11 --perft

import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v11/core/board.dart';
import 'package:ace/engines/v11/core/zobrist.dart';
import 'package:ace/engines/v11/search/searcher.dart';
import 'package:ace/engines/v11/v11_engine.dart';

class BenchPosition {
  final String name;
  final String fen;
  const BenchPosition(this.name, this.fen);
}

const List<BenchPosition> positions = [
  BenchPosition('start', 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
  BenchPosition('open middlegame', 'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10'),
  BenchPosition('closed middlegame', 'r1bqk2r/ppp1bppp/2n1pn2/3p4/2PP4/2N2NP1/PP2PP1P/R1BQKB1R w KQkq - 2 6'),
  BenchPosition('kiwipete', 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1'),
  BenchPosition('tactical (WAC.003)', '5rk1/1ppb3p/p1pb4/6q1/3P1p1r/2P1R2P/PP1BQ1P1/5RKN w - - 0 1'),
  BenchPosition('promotions / ep', 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1'),
  BenchPosition('KPK endgame', '8/8/8/4k3/8/4K3/4P3/8 w - - 0 1'),
  BenchPosition('K+P endgame, locked', '8/5pk1/6p1/8/5PK1/6P1/8/8 w - - 0 1'),
  BenchPosition('rook endgame', '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1'),
  BenchPosition('in check at root', 'rnbqkbnr/ppp2ppp/8/1B1pp3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 1 3'),
];

class PerftCase {
  final String name;
  final String fen;
  final int depth;
  final int nodes;
  final int captures;
  const PerftCase(this.name, this.fen, this.depth, this.nodes, this.captures);
}

// Known-correct values (chessprogramming.org perft results).
const List<PerftCase> perftCases = [
  PerftCase('start', 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 4, 197281, 1576),
  PerftCase('kiwipete', 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', 3, 97862, 17102),
  PerftCase('position 3 (ep)', '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', 4, 43238, 3348),
  PerftCase('position 4 (promotions)', 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', 3, 9467, 1021),
];

String _pad(Object v, int w) => v.toString().padLeft(w);

void main(List<String> args) {
  int depth = 7;
  bool runPerft = false;
  String? only;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--depth':
        depth = int.parse(args[++i]);
        break;
      case '--perft':
        runPerft = true;
        break;
      case '--only':
        only = args[++i];
        break;
      default:
        print('Unknown argument ${args[i]}');
        return;
    }
  }

  Zobrist.ensureInitialised();

  final selected = positions.where((p) => only == null || p.name.contains(only)).toList();
  print('v11 benchmark, fixed depth $depth, ${selected.length} positions\n');
  print('${'position'.padRight(22)}${'move'.padRight(7)}${_pad('eval', 8)}${_pad('nodes', 12)}${_pad('qNodes', 12)}'
      '${_pad('betaCuts', 11)}${_pad('1stCuts', 10)}${_pad('dMoves', 10)}${_pad('ms', 8)}${_pad('knps', 8)}');

  int totalNodes = 0, totalQ = 0, totalBeta = 0, totalFirst = 0, totalMs = 0, totalDMoves = 0;
  for (final p in selected) {
    // Fresh searcher per position so the transposition table never leaks between positions.
    final searcher = Searcher();
    final board = Board.fromFEN(p.fen);
    final move = searcher.getBestMove(board, depth: depth);
    final SearchStats s = searcher.stats;
    final ms = s.elapsed.inMilliseconds;
    final knps = ms == 0 ? 0 : s.nodes ~/ ms;

    // Eval is from the side to move's point of view.
    print('${p.name.padRight(22)}${(move?.uci ?? '-').padRight(7)}${_pad(s.eval ?? 0, 8)}${_pad(s.nodes, 12)}'
        '${_pad(s.qNodes, 12)}${_pad(s.betaCutoffs, 11)}${_pad(s.firstMoveCutoffs, 10)}'
        '${_pad(s.deltaPrunedMoves, 10)}${_pad(ms, 8)}${_pad(knps, 8)}');

    totalDMoves += s.deltaPrunedMoves;
    totalNodes += s.nodes;
    totalQ += s.qNodes;
    totalBeta += s.betaCutoffs;
    totalFirst += s.firstMoveCutoffs;
    totalMs += ms;
  }

  final totalKnps = totalMs == 0 ? 0 : totalNodes ~/ totalMs;
  final firstPct = totalBeta == 0 ? 0.0 : 100 * totalFirst / totalBeta;
  print('\nTOTAL nodes=$totalNodes qNodes=$totalQ betaCuts=$totalBeta firstMoveCuts=$totalFirst '
      '(${firstPct.toStringAsFixed(1)}%) deltaPruned=$totalDMoves '
      'time=${totalMs}ms knps=$totalKnps');

  if (runPerft) _runPerft();
}

void _runPerft() {
  print('\nperft (checks known counts)');
  final engine = V11Engine();
  int totalNodes = 0, totalMs = 0;
  bool allOk = true;
  for (final c in perftCases) {
    final sw = Stopwatch()..start();
    final result = engine.perft(c.fen, c.depth);
    sw.stop();
    final ok = result.nodes == c.nodes && result.captures == c.captures;
    allOk &= ok;
    totalNodes += result.nodes;
    totalMs += sw.elapsedMilliseconds;
    print('${c.name.padRight(26)}d${c.depth} nodes=${_pad(result.nodes, 9)} captures=${_pad(result.captures ?? '-', 8)} '
        '${_pad(sw.elapsedMilliseconds, 6)}ms  ${ok ? 'OK' : 'MISMATCH (expected ${c.nodes} / ${c.captures})'}');
  }
  final knps = totalMs == 0 ? 0 : totalNodes ~/ totalMs;
  print('PERFT ${allOk ? 'PASS' : 'FAIL'} nodes=$totalNodes time=${totalMs}ms knps=$knps');
}
