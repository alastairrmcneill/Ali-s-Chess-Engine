import 'package:ace/match_manager/elo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Elo.calculate', () {
    // Independently computed reference values from the plan, n = 1000 games each.
    void expectResult(int w, int d, int l, double score, double elo, double errorMargin, double los) {
      final result = Elo.calculate(w, d, l);
      expect(result.score, closeTo(score, 0.001));
      expect(result.elo, closeTo(elo, 0.05));
      expect(result.errorMargin, closeTo(errorMargin, 0.05));
      expect(result.likelihoodOfSuperiority, closeTo(los, 0.0005));
    }

    test('even score (400/200/400) gives 0 Elo', () {
      expectResult(400, 200, 400, 0.5000, 0, 19.28, 0.5000);
    });

    test('450/200/350 gives +34.86 Elo', () {
      expectResult(450, 200, 350, 0.5500, 34.86, 19.35, 0.9998);
    });

    test('600/300/100 gives +190.85 Elo', () {
      expectResult(600, 300, 100, 0.7500, 190.85, 19.30, 1.0000);
    });

    test('no games played gives score 0.5, Elo 0 and an infinite error margin', () {
      final result = Elo.calculate(0, 0, 0);
      expect(result.score, 0.5);
      expect(result.elo, 0);
      expect(result.errorMargin, double.infinity);
      expect(result.likelihoodOfSuperiority, 0.5);
    });

    test('a total whitewash gives an infinite Elo difference', () {
      final result = Elo.calculate(10, 0, 0);
      expect(result.elo, double.infinity);

      final reverse = Elo.calculate(0, 0, 10);
      expect(reverse.elo, double.negativeInfinity);
    });
  });

  group('Elo.fromScore', () {
    test('a score of 0.5 is 0 Elo', () {
      expect(Elo.fromScore(0.5), 0);
    });

    test('a score of 0 or 1 is ±infinity', () {
      expect(Elo.fromScore(0), double.negativeInfinity);
      expect(Elo.fromScore(1), double.infinity);
    });
  });

  group('Elo.likelihoodOfSuperiority', () {
    test('equal wins and losses give 0.5', () {
      expect(Elo.likelihoodOfSuperiority(5, 5), 0.5);
      expect(Elo.likelihoodOfSuperiority(0, 0), 0.5);
    });

    test('more wins than losses gives > 0.5', () {
      expect(Elo.likelihoodOfSuperiority(10, 2), greaterThan(0.5));
    });

    test('more losses than wins gives < 0.5', () {
      expect(Elo.likelihoodOfSuperiority(2, 10), lessThan(0.5));
    });
  });
}
