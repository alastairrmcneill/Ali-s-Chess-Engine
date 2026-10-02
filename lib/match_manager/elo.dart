import 'dart:math';

class EloResult {
  final double score; // 0..1 from engine A's point of view
  final double elo; // may be ±infinity for a whitewash
  final double errorMargin; // 95% confidence, ± Elo
  final double likelihoodOfSuperiority; // 0..1

  const EloResult(this.score, this.elo, this.errorMargin, this.likelihoodOfSuperiority);
}

class Elo {
  /// Elo difference for an expected score [score] (0..1).
  static double fromScore(double score) {
    if (score <= 0) return double.negativeInfinity;
    if (score >= 1) return double.infinity;
    return -400 * log(1 / score - 1) / ln10;
  }

  /// Score, Elo difference, 95% error margin and likelihood of superiority for A's [wins]/[draws]/[losses].
  static EloResult calculate(int wins, int draws, int losses) {
    final n = wins + draws + losses;
    if (n == 0) return const EloResult(0.5, 0, double.infinity, 0.5);

    final w = wins / n, d = draws / n, l = losses / n;
    final score = w + d / 2;
    final variance = w * pow(1 - score, 2) + d * pow(0.5 - score, 2) + l * pow(score, 2);
    final standardError = sqrt(variance / n);

    // Clamp so the bounds stay finite.
    double clamp(double s) => s.clamp(1e-6, 1 - 1e-6).toDouble();
    final upper = fromScore(clamp(score + 1.959964 * standardError));
    final lower = fromScore(clamp(score - 1.959964 * standardError));

    return EloResult(score, fromScore(score), (upper - lower) / 2, likelihoodOfSuperiority(wins, losses));
  }

  static double likelihoodOfSuperiority(int wins, int losses) {
    if (wins == losses) return 0.5;
    return 0.5 * (1 + _erf((wins - losses) / sqrt(2 * (wins + losses))));
  }

  /// Abramowitz & Stegun 7.1.26, accurate to about 1e-7.
  static double _erf(double x) {
    final sign = x < 0 ? -1 : 1;
    x = x.abs();
    final t = 1 / (1 + 0.3275911 * x);
    final y = 1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) *
            t *
            exp(-x * x);
    return sign * y;
  }
}
