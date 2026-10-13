import 'package:ace/engines/v8/core/board.dart';
import 'package:ace/engines/v8/core/move.dart';
import 'package:ace/engines/v8/core/move_generator.dart';
import 'package:ace/engines/v8/core/zobrist.dart';
import 'package:ace/engines/v8/search/move_ordering.dart';
import 'package:ace/engines/v8/search/searcher.dart';
import 'package:ace/engines/v8/search/transposition_table.dart';
import 'package:flutter_test/flutter_test.dart';

const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

Move _move(int from, int to, {int promotion = 0}) => Move(startingSquare: from, targetSquare: to, promotion: promotion);

void main() {
  setUpAll(() => Zobrist());

  group('packMove', () {
    test('is unique for every from/to/promotion combination', () {
      final seen = <int>{};
      for (int from = 0; from < 64; from++) {
        for (int to = 0; to < 64; to++) {
          if (from == to) continue;
          for (int promotion = 0; promotion <= 4; promotion++) {
            expect(seen.add(TranspositionTable.packMove(_move(from, to, promotion: promotion))), isTrue);
          }
        }
      }
    });

    test('a real move is never 0, and Move.invalid packs to 0 ("no move")', () {
      expect(TranspositionTable.packMove(_move(0, 1)), isNot(0));
      expect(TranspositionTable.packMove(Move.invalid), 0);
    });

    test('ignores flags that do not identify a move', () {
      final plain = _move(12, 28);
      final flagged = Move(startingSquare: 12, targetSquare: 28, pawnTwoForward: true, enPassantCapture: true);
      expect(TranspositionTable.packMove(flagged), TranspositionTable.packMove(plain));
    });
  });

  group('TranspositionTable', () {
    late TranspositionTable tt;

    setUp(() => tt = TranspositionTable(sizePower: 4)); // 16 slots, so collisions are easy to make

    test('size is a power of two and index stays in range, including negative keys', () {
      expect(tt.size, 16);
      for (final key in [0, 1, 15, 16, 17, -1, -16, 0x7fffffffffffffff, -0x8000000000000000]) {
        expect(tt.index(key), inInclusiveRange(0, 15));
        expect(tt.index(key), key & 15);
      }
    });

    test('empty table never hits, even for key 0', () {
      expect(tt.probe(0), isNull);
      expect(tt.probe(123456789), isNull);
    });

    test('store then probe round trips every field', () {
      const key = 0x1234567890abcdef;
      tt.store(key, -250, _move(12, 28), 7, TranspositionTable.lower);

      final slot = tt.probe(key);
      expect(slot, isNotNull);
      expect(tt.scoreAt(slot!), -250);
      expect(tt.depthAt(slot), 7);
      expect(tt.flagAt(slot), TranspositionTable.lower);
      expect(tt.moveAt(slot), TranspositionTable.packMove(_move(12, 28)));
    });

    test('large mate scores survive the Int32 storage', () {
      tt.store(5, 999999990, _move(1, 2), 3, TranspositionTable.exact);
      tt.store(6, -999999990, _move(1, 2), 3, TranspositionTable.exact);
      expect(tt.scoreAt(tt.probe(5)!), 999999990);
      expect(tt.scoreAt(tt.probe(6)!), -999999990);
    });

    test('a different key in the same slot misses (full key verified)', () {
      tt.store(3, 10, _move(1, 2), 1, TranspositionTable.exact);
      expect(tt.index(3 + 16), tt.index(3));
      expect(tt.probe(3 + 16), isNull);
      expect(tt.probe(3), isNotNull);
    });

    test('always-replace: a colliding store evicts the old entry', () {
      tt.store(3, 10, _move(1, 2), 9, TranspositionTable.exact);
      tt.store(3 + 16, 20, _move(3, 4), 1, TranspositionTable.upper);
      expect(tt.probe(3), isNull);
      final slot = tt.probe(3 + 16)!;
      expect(tt.scoreAt(slot), 20);
      expect(tt.flagAt(slot), TranspositionTable.upper);
    });

    test('storing the same key again overwrites it', () {
      tt.store(7, 10, _move(1, 2), 2, TranspositionTable.upper);
      tt.store(7, 55, _move(5, 6), 4, TranspositionTable.exact);
      final slot = tt.probe(7)!;
      expect(tt.scoreAt(slot), 55);
      expect(tt.depthAt(slot), 4);
      expect(tt.flagAt(slot), TranspositionTable.exact);
      expect(tt.moveAt(slot), TranspositionTable.packMove(_move(5, 6)));
    });

    test('depth is clamped to the Int8 range', () {
      tt.store(7, 0, _move(1, 2), 500, TranspositionTable.exact);
      expect(tt.depthAt(tt.probe(7)!), 127);
    });

    test('storing Move.invalid keeps "no move" as 0', () {
      tt.store(7, 0, Move.invalid, 2, TranspositionTable.upper);
      expect(tt.moveAt(tt.probe(7)!), 0);
    });

    test('flag constants are distinct and non-zero (0 means empty)', () {
      final flags = {TranspositionTable.exact, TranspositionTable.lower, TranspositionTable.upper};
      expect(flags.length, 3);
      expect(flags.contains(0), isFalse);
    });
  });

  group('mate score adjustment', () {
    final searcher = Searcher();
    final mated = searcher.mateScore; // -999999999

    test('non-mate scores pass through unchanged', () {
      for (final s in [0, 40, -40, 12345, -12345, 99000, -99000]) {
        expect(searcher.toTT(s, 9), s);
        expect(searcher.fromTT(s, 9), s);
      }
    });

    test('isMate detects mate scores near the limit only', () {
      expect(searcher.isMate(mated + 5), isTrue);
      expect(searcher.isMate(-mated - 5), isTrue);
      expect(searcher.isMate(500000), isFalse);
    });

    test('fromTT(toTT(x, p), p) == x for mate and non-mate scores', () {
      final scores = [0, 321, -321, mated, mated + 1, mated + 17, -(mated + 1), -(mated + 17), -mated];
      for (final s in scores) {
        for (final ply in [0, 1, 2, 7, 30]) {
          expect(searcher.fromTT(searcher.toTT(s, ply), ply), s, reason: 'score $s ply $ply');
        }
      }
    });

    test('stored mate score is independent of the ply it was found at', () {
      // Being mated 3 plies below the node: the node at ply 4 sees mateScore+7, the node at ply 10 sees mateScore+13.
      expect(searcher.toTT(mated + 7, 4), searcher.toTT(mated + 13, 10));
      // Delivering mate 3 plies below the node.
      expect(searcher.toTT(-mated - 7, 4), searcher.toTT(-mated - 13, 10));
    });

    test('a stored mate is re-based to the probing ply', () {
      final stored = searcher.toTT(mated + 7, 4); // mated in 3 plies from the node
      expect(searcher.fromTT(stored, 10), mated + 13);
    });

    test('winning mate scores shrink with ply, losing ones grow in magnitude', () {
      expect(searcher.toTT(-mated - 6, 6), -mated);
      expect(searcher.toTT(mated + 6, 6), mated);
    });
  });

  group('MoveOrdering with a TT move', () {
    test('the TT move sorts first, whatever it is', () {
      final board = Board.fromFEN(_start);
      final moves = MoveGenerator().generateLegalMoves(board);

      for (final target in [moves.first, moves.last, moves[moves.length ~/ 2]]) {
        final ordered = MoveOrdering().orderMoves(board, List.of(moves), ttMove: TranspositionTable.packMove(target));
        expect(TranspositionTable.packMove(ordered.first), TranspositionTable.packMove(target));
        expect(ordered.length, moves.length);
      }
    });

    test('ttMove 0 leaves ordering alone and keeps every move', () {
      final board = Board.fromFEN(_start);
      final moves = MoveGenerator().generateLegalMoves(board);
      final ordered = MoveOrdering().orderMoves(board, List.of(moves));
      expect(ordered.map((m) => m.uci).toSet(), moves.map((m) => m.uci).toSet());
    });

    test('a TT move that is not legal here changes nothing', () {
      final board = Board.fromFEN(_start);
      final moves = MoveGenerator().generateLegalMoves(board);
      final plain = MoveOrdering().orderMoves(board, List.of(moves)).map((m) => m.uci).toList();
      final bogus = MoveOrdering().orderMoves(board, List.of(moves), ttMove: TranspositionTable.packMove(_move(0, 63)));
      expect(bogus.map((m) => m.uci).toList(), plain);
    });
  });

  group('Searcher with the table', () {
    // Kings and pawns only: lots of transpositions.
    const fen = '8/k7/3p4/p2P1p2/P2P1P2/8/8/K7 w - - 0 1';

    test('searching the same position twice gives the same move and eval, and the table gets hits', () {
      final searcher = Searcher();
      final board = Board.fromFEN(fen);

      final first = searcher.getBestMove(board, depth: 6);
      final firstEval = searcher.bestEval;
      final second = searcher.getBestMove(board, depth: 6);

      expect(first, isNotNull);
      expect(second!.uci, first!.uci);
      expect(searcher.bestEval, firstEval);
      expect(searcher.stats.transpositions, greaterThan(0));
    });

    test('finds a mate in one and reports the same distance on a repeat search', () {
      const mateFen = '6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1';
      final searcher = Searcher();
      final board = Board.fromFEN(mateFen);

      expect(searcher.getBestMove(board, depth: 4)!.uci, 'a1a8');
      final eval = searcher.bestEval;
      expect(searcher.getBestMove(board, depth: 4)!.uci, 'a1a8');
      expect(searcher.bestEval, eval);
    });

    test('board is left unchanged by the search', () {
      final board = Board.fromFEN(fen);
      final key = board.zobristKey;
      Searcher().getBestMove(board, depth: 4);
      expect(board.zobristKey, key);
    });
  });
}
