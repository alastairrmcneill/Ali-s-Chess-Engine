// Explains why v12 played a move. Run: dart run tool/explain_v12.dart <game.pgn> --at 8b,10b [--depth N] [--movetime ms]
//
// Replays the PGN to the position before each requested move (e.g. "8b" = Black's 8th move, "12w" = White's 12th)
// and prints:
//   1. The static eval of the position.
//   2. What v12 picks with the given time limit (same call the app makes), and how deep it got.
//   3. For every depth up to --depth: each root move searched with a full window, so every score is exact
//      rather than a bound, with its principal variation from the transposition table. The game move is marked.
// Read it like this: if the game move is top at the depth the engine reached in time but drops at a deeper depth,
// it was a horizon problem (not enough depth). If it stays top at every depth, the evaluation (or a pruning rule)
// likes it, and the PV shows the line the engine believes in.
//
// Scores are centipawns from the side to move's point of view.

import 'dart:io';

import 'package:ace/chess_core/notation/san.dart';
import 'package:ace/chess_core/rules/board.dart' as core;
import 'package:ace/chess_core/rules/move_generator.dart' as core;
import 'package:ace/engines/v12/core/board.dart';
import 'package:ace/engines/v12/core/move.dart';
import 'package:ace/engines/v12/core/move_generator.dart';
import 'package:ace/engines/v12/core/zobrist.dart';
import 'package:ace/engines/v12/search/searcher.dart';

const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const int inf = 1000000000;

void main(List<String> args) {
  if (args.isEmpty || !args.contains('--at')) {
    stderr.writeln('usage: dart run tool/explain_v12.dart <game.pgn> --at 8b,10b [--depth 6] [--movetime 1000] [--top 8]');
    exit(64);
  }
  String opt(String name, String fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final sanMoves = parsePgn(File(args[0]).readAsStringSync());
  final uciMoves = sanToUci(sanMoves);
  final maxDepth = int.parse(opt('--depth', '6'));
  final moveTime = Duration(milliseconds: int.parse(opt('--movetime', '1000')));
  final top = int.parse(opt('--top', '8'));

  Zobrist.ensureInitialised();
  for (final at in opt('--at', '').split(',')) {
    final fullMove = int.parse(at.substring(0, at.length - 1));
    final ply = (fullMove - 1) * 2 + (at.endsWith('b') ? 1 : 0);
    if (ply >= uciMoves.length) {
      print('$at: game has no such move');
      continue;
    }
    explain(at, sanMoves[ply], uciMoves.sublist(0, ply), uciMoves[ply], maxDepth, moveTime, top);
  }
}

void explain(String label, String playedSan, List<String> history, String played, int maxDepth, Duration moveTime, int top) {
  print('\n=== $label: game move $playedSan ($played) ===');

  // What the engine actually does with a time limit, on a fresh searcher (the app's TT from earlier moves is not
  // reproduced, so depth can differ slightly from the real game).
  final timed = Searcher();
  final board = boardAfter(history);
  print('static eval: ${timed.evaluator.evaluate(board)}');
  final choice = timed.getBestMove(board, timeLimit: moveTime);
  print('with ${moveTime.inMilliseconds}ms: plays ${choice?.uci} at depth ${timed.stats.depth}, '
      'eval ${timed.bestEval}, ${timed.stats.nodes} nodes');

  // Full-window score for every root move, one depth at a time. Slow, but every number is exact.
  final searcher = Searcher();
  final b = boardAfter(history);
  searcher.board = b;
  final rootMoves = MoveGenerator().generate(b);
  for (int depth = 1; depth <= maxDepth; depth++) {
    final sw = Stopwatch()..start();
    final scored = <(Move, int, List<String>)>[];
    for (final move in rootMoves) {
      b.makeMove(move);
      final score = -searcher.search(depth - 1, 1, -inf, inf);
      final pv = principalVariation(searcher, b, depth - 1);
      b.unMakeMove(move);
      scored.add((move, score, [move.uci, ...pv]));
    }
    scored.sort((x, y) => y.$2.compareTo(x.$2));
    final rank = scored.indexWhere((s) => s.$1.uci == played) + 1;
    print('\n-- depth $depth (${sw.elapsedMilliseconds}ms) game move ranked $rank/${scored.length} --');
    for (int i = 0; i < scored.length; i++) {
      final (move, score, pv) = scored[i];
      if (i >= top && move.uci != played) continue;
      final mark = move.uci == played ? '>>' : '  ';
      print('$mark ${score.toString().padLeft(7)}  ${pv.join(' ')}');
    }
  }
}

/// Follows best moves stored in the TT. Best effort: entries can be overwritten.
List<String> principalVariation(Searcher searcher, Board board, int length) {
  final pv = <String>[];
  final made = <Move>[];
  for (int i = 0; i < length + 4; i++) {
    final slot = searcher.tt.probe(board.zobristKey);
    if (slot == null) break;
    final ttMove = searcher.tt.moveAt(slot);
    final legal = MoveGenerator().generate(board).where((m) => m == ttMove);
    if (ttMove.isNoMove || legal.isEmpty) break;
    pv.add(ttMove.uci);
    board.makeMove(ttMove);
    made.add(ttMove);
    if (board.isRepetition()) break;
  }
  for (final m in made.reversed) {
    board.unMakeMove(m);
  }
  return pv;
}

Board boardAfter(List<String> uciMoves) {
  final board = Board.fromFEN(startFen);
  final gen = MoveGenerator();
  for (final uci in uciMoves) {
    board.makeMove(gen.generate(board).firstWhere((m) => m.uci == uci));
  }
  return board;
}

/// Strips headers, comments, variations, NAGs, move numbers and the result.
List<String> parsePgn(String pgn) {
  var text = pgn.replaceAll(RegExp(r'^\[.*\]\s*$', multiLine: true), '').replaceAll(RegExp(r'\{[^}]*\}'), ' ');
  while (text.contains('(')) {
    text = text.replaceAll(RegExp(r'\([^()]*\)'), ' ');
  }
  return text
      .replaceAll(RegExp(r'\$\d+'), ' ')
      .replaceAll(RegExp(r'\d+\.(\.\.)?'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !const ['1-0', '0-1', '1/2-1/2', '*'].contains(t))
      .toList();
}

List<String> sanToUci(List<String> sanMoves) {
  final board = core.Board.fromFEN(startFen);
  final gen = core.MoveGenerator();
  final out = <String>[];
  for (final san in sanMoves) {
    final move = San.toLegalMove(board, san, gen.generateLegalMoves(board));
    if (move == null) throw FormatException('illegal SAN in PGN', san);
    final promo = move.promotion == 0 ? '' : ' qnrb'[move.promotion];
    out.add(move.toChessNotation() + promo);
    board.makeMove(move);
  }
  return out;
}
