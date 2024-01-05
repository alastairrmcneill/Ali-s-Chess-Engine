import 'dart:math' as math;

extension ListExtension on Iterable<int> {
  int get max => reduce(math.max);

  int get min => reduce(math.min);
}
