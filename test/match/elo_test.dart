import 'package:ace/match/elo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Values computed independently (see the plan, §5.3).
  final cases = [
    // wins, draws, losses, score, elo, ±, LOS
    (400, 200, 400, 0.5, 0.0, 19.28, 0.5),
    (450, 200, 350, 0.55, 34.86, 19.35, 0.9998),
    (600, 300, 100, 0.75, 190.85, 19.30, 1.0),
  ];

  for (final (w, d, l, score, elo, margin, los) in cases) {
    test('+$w =$d -$l', () {
      final result = Elo.calculate(w, d, l);
      expect(result.score, closeTo(score, 0.0001));
      expect(result.elo, closeTo(elo, 0.05));
      expect(result.errorMargin, closeTo(margin, 0.05));
      expect(result.likelihoodOfSuperiority, closeTo(los, 0.0001));
    });
  }

  test('whitewash gives infinite Elo but a finite margin', () {
    final result = Elo.calculate(10, 0, 0);
    expect(result.elo, double.infinity);
    expect(result.errorMargin.isFinite, isTrue);
  });

  test('no games', () {
    expect(Elo.calculate(0, 0, 0).elo, 0);
    expect(Elo.likelihoodOfSuperiority(5, 5), 0.5);
  });
}
