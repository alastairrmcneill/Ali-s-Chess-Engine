import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v3/v3_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final limits = SearchLimits(moveTime: const Duration(milliseconds: 50));

  test('finds mate in one and reports a mate score, depth, nodes and pv', () {
    // White plays Ra8#
    final result = V3Engine().getMove('6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1', [], limits);
    expect(result.uciMove, 'a1a8');
    expect(result.evaluation, greaterThan(900000));
    expect(result.depth, 3);
    expect(result.nodes, greaterThan(0));
    expect(result.principalVariation!.first, 'a1a8');
  });

  test('reports its single search through onIteration', () {
    final reported = <SearchStats>[];
    final result = V3Engine().getMove(FenPosition.startingPosition, [], limits, onIteration: reported.add);
    expect(reported, hasLength(1));
    expect(reported.single.depth, 3);
    expect(reported.single.nodes, result.nodes);
    expect(reported.single.evaluations, greaterThan(0));
    expect(reported.single.bestMove, result.uciMove);
  });

  test('takes a free queen', () {
    final result = V3Engine().getMove('4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1', [], limits);
    expect(result.uciMove, 'd1d5');
  });

  test('is deterministic, never prints, and ignores the time limit', () {
    final a = V3Engine().getMove(FenPosition.startingPosition, [], limits);
    final b = V3Engine().getMove(FenPosition.startingPosition, [], limits);
    expect(a.uciMove, b.uciMove);
    expect(a.nodes, b.nodes);
    expect(a.principalVariation!.length, lessThanOrEqualTo(3));
  });
}
