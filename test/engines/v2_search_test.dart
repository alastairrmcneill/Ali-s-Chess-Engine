import 'package:ace/engines/v2/core/board.dart';
import 'package:ace/engines/v2/core/move_generator.dart';
import 'package:ace/engines/v2/core/zobrist.dart';
import 'package:ace/engines/v2/search/searcher.dart';
import 'package:ace/engines/v2/v2_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _kiwipete = 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1';
const _position3 = '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1';
const _position4 = 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1';
const _position5 = 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8';

String _uci(move) => V2Engine().moveToUci(move);

void _play(Board board, List<String> ucis) {
  for (final uci in ucis) {
    final move = MoveGenerator().generateLegalMoves(board).firstWhere((m) => _uci(m) == uci);
    board.makeMove(move);
  }
}

int _perft(Board board, int depth) {
  final moves = MoveGenerator().generateLegalMoves(board);
  if (depth == 1) return moves.length;
  var nodes = 0;
  for (final move in moves) {
    board.makeMove(move);
    nodes += _perft(board, depth - 1);
    board.unMakeMove(move);
  }
  return nodes;
}

/// Everything make/unmake must restore.
List<Object> _snapshot(Board b) => [
      b.position.join(','),
      b.whiteToPlay,
      b.whiteCastleKingSide,
      b.whiteCastleQueenSide,
      b.blackCastleKingSide,
      b.blackCastleQueenSide,
      b.enPassantSquare,
      b.zobristKey,
      b.fiftyMoveRule,
      b.plyCount,
    ];

void _walkAndCheckUnmake(Board board, int depth) {
  if (depth == 0) return;
  final before = _snapshot(board);
  for (final move in MoveGenerator().generateLegalMoves(board)) {
    board.makeMove(move);
    _walkAndCheckUnmake(board, depth - 1);
    board.unMakeMove(move);
    expect(_snapshot(board), before, reason: 'make/unmake of ${_uci(move)} did not restore the board');
  }
}

/// Flips the board vertically and swaps colours, so White and Black trade places.
String _mirror(String fen) {
  final parts = fen.split(' ');
  final ranks = parts[0].split('/').reversed.map((rank) {
    return rank.split('').map((c) {
      if (int.tryParse(c) != null) return c;
      return c == c.toUpperCase() ? c.toLowerCase() : c.toUpperCase();
    }).join();
  }).join('/');
  final side = parts[1] == 'w' ? 'b' : 'w';
  final castling = parts[2] == '-'
      ? '-'
      : (parts[2].split('').map((c) => c == c.toUpperCase() ? c.toLowerCase() : c.toUpperCase()).toList()
            ..sort((a, b) {
              // KQkq ordering
              const order = 'KQkq';
              return order.indexOf(a).compareTo(order.indexOf(b));
            }))
          .join();
  var enPassant = parts[3];
  if (enPassant != '-') {
    enPassant = '${enPassant[0]}${9 - int.parse(enPassant[1])}';
  }
  return [ranks, side, castling, enPassant, ...parts.sublist(4)].join(' ');
}

({String? move, int eval, int nodes}) _search(String fen, int depth) {
  final searcher = Searcher();
  final move = searcher.getBestMove(Board.fromFEN(fen), depth: depth);
  return (move: move == null ? null : _uci(move), eval: searcher.bestEval, nodes: searcher.nodes);
}

void main() {
  setUpAll(() => Zobrist());

  group('v2 move generator (perft)', () {
    final cases = <String, (String, List<int>)>{
      'start position': (_start, [20, 400, 8902, 197281]),
      'kiwipete': (_kiwipete, [48, 2039, 97862]),
      'position 3': (_position3, [14, 191, 2812, 43238]),
      'position 4': (_position4, [6, 264, 9467]),
      'position 5': (_position5, [44, 1486, 62379]),
    };
    cases.forEach((name, data) {
      final (fen, expected) = data;
      for (var i = 0; i < expected.length; i++) {
        test('$name depth ${i + 1} = ${expected[i]}', () {
          expect(_perft(Board.fromFEN(fen), i + 1), expected[i]);
        });
      }
    });
  });

  group('v2 make/unmake', () {
    for (final entry
        in {'start': _start, 'kiwipete': _kiwipete, 'position 4': _position4, 'position 5': _position5}.entries) {
      test('restores the board for every move, ${entry.key}', () {
        _walkAndCheckUnmake(Board.fromFEN(entry.value), 3);
      });
    }
  });

  group('v2 search', () {
    test('without pruning, nodes = perft(1..depth-1) summed plus the root', () {
      // search() counts one node per visited position below the root, root moves included.
      final board = Board.fromFEN(_kiwipete);
      var expected = 0;
      for (var d = 1; d <= 2; d++) {
        expected += _perft(Board.fromFEN(_kiwipete), d);
      }
      expect(_search(_kiwipete, 3).nodes, expected + _perft(board, 3));
    });

    test('does not mutate the board it is given', () {
      final board = Board.fromFEN(_kiwipete);
      final before = _snapshot(board);
      Searcher().getBestMove(board, depth: 3);
      expect(_snapshot(board), before);
    });

    test('finds a back rank mate in 1 as White', () {
      expect(_search('6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1', 2).move, 'a1a8');
    });

    test('finds a back rank mate in 1 as Black', () {
      expect(_search('r3k3/8/8/8/8/8/5PPP/6K1 b - - 0 1', 2).move, 'a8a1');
    });

    test('takes a free queen', () {
      expect(_search('4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1', 2).move, 'd1d5');
    });

    test('moves its queen when a pawn attacks it', () {
      // The b6 pawn attacks the queen on c5. Moving any other piece loses the queen at depth 2.
      expect(_search('4k3/8/1p6/2Q5/8/8/8/4K3 w - - 0 1', 2).move, startsWith('c5'));
    });

    test('plays the mate instead of stalemating', () {
      const fen = 'k7/2Q5/1K6/8/8/8/8/8 w - - 0 1';
      final board = Board.fromFEN(fen);
      final generator = MoveGenerator();
      final move = generator.generateLegalMoves(board).firstWhere((m) => _uci(m) == _search(fen, 2).move);
      board.makeMove(move);
      expect(generator.generateLegalMoves(board), isEmpty);
      expect(generator.inCheck, isTrue, reason: 'no legal moves without check is stalemate');
    });

    test('returns no move when there are no legal moves', () {
      expect(_search('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1', 3).move, isNull);
    });

    test('scores a position the same from either colour (mirror symmetry)', () {
      for (final fen in [_start, _kiwipete, _position5]) {
        final original = _search(fen, 3);
        final mirrored = _search(_mirror(fen), 3);
        expect(mirrored.eval, original.eval, reason: 'mirror of $fen');
        expect(mirrored.nodes, original.nodes, reason: 'mirror of $fen');
      }
    });

    test('stops near the time limit and still returns a legal move', () {
      final searcher = Searcher();
      final sw = Stopwatch()..start();
      final move =
          searcher.getBestMove(Board.fromFEN(_kiwipete), depth: 8, timeLimit: const Duration(milliseconds: 200));
      expect(sw.elapsedMilliseconds, lessThan(400));
      expect(searcher.aborted, isTrue);
      expect(move, isNotNull);
    });

    test('counts the starting position in the repetition history', () {
      final board = Board.fromFEN(_start);
      expect(board.hashHistory[board.zobristKey], 1);
      _play(board, ['g1f3', 'g8f6', 'f3g1', 'f6g8']);
      expect(board.hashHistory[board.zobristKey], 2);
    });

    test('scores a move that repeats a position as a draw', () {
      // Black is a rook down with exactly one legal move (Ka8-a7), which repeats the start position.
      const fen = '8/k1K5/8/8/8/8/8/7R w - - 0 1';

      final repeating = Board.fromFEN(fen);
      _play(repeating, ['h1h2', 'a7a8', 'h2h1']);
      final withHistory = Searcher();
      expect(_uci(withHistory.getBestMove(repeating, depth: 2)!), 'a8a7');
      expect(withHistory.bestEval, 0);

      // Same position without the history: nothing repeats, so Black is simply a rook down.
      final fresh = Board.fromFEN('k7/2K5/8/8/8/8/8/7R b - - 0 1');
      final withoutHistory = Searcher();
      withoutHistory.getBestMove(fresh, depth: 2);
      expect(withoutHistory.bestEval, lessThan(0));
    });

    test('scores a position at the fifty move limit as a draw', () {
      // White is a rook up, but 100 half moves without a capture or pawn move is a draw.
      final board = Board.fromFEN('4k3/8/8/8/8/8/8/R3K3 w - - 99 80');
      final searcher = Searcher();
      searcher.getBestMove(board, depth: 2);
      expect(searcher.bestEval, 0);
    });

    test('deeper search never reports fewer nodes', () {
      var last = 0;
      for (var depth = 1; depth <= 3; depth++) {
        final nodes = _search(_kiwipete, depth).nodes;
        expect(nodes, greaterThan(last));
        last = nodes;
      }
    });
  });
}
