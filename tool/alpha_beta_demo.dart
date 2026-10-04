// Toy alpha-beta walkthrough. Run: dart run tool/alpha_beta_demo.dart
//
// Same shape as Searcher.search (negamax, fail-hard) but on a hand-made tree:
// White picks one of 4 moves (A-D), Black replies with one of 3, then we evaluate.
// Leaf scores are from White's point of view (+ good for White).
//
//   root (White)
//   ├─ A ── 3   5  10
//   ├─ B ── 2   4   6
//   ├─ C ── 7   4   9
//   └─ D ── 6   1   8

const inf = 1000;

class Node {
  final String name;
  final int? leaf;
  final List<Node> children;
  Node.leaf(this.name, this.leaf) : children = const [];
  Node.branch(this.name, this.children) : leaf = null;
}

final tree = Node.branch('root', [
  Node.branch('A', [Node.leaf('A1', 3), Node.leaf('A2', 5), Node.leaf('A3', 10)]),
  Node.branch('B', [Node.leaf('B1', 2), Node.leaf('B2', 4), Node.leaf('B3', 6)]),
  Node.branch('C', [Node.leaf('C1', 7), Node.leaf('C2', 4), Node.leaf('C3', 9)]),
  Node.branch('D', [Node.leaf('D1', 6), Node.leaf('D2', 1), Node.leaf('D3', 8)]),
]);

int visited = 0;
bool prune = true;
bool verbose = true;

void log(int ply, String s) {
  if (verbose) print('${'    ' * ply}$s');
}

/// [whiteToMove] only used to turn the White-POV leaf into a side-to-move score.
int search(Node n, int ply, bool whiteToMove, int alpha, int beta) {
  visited++;
  if (n.leaf != null) {
    final score = whiteToMove ? n.leaf! : -n.leaf!;
    log(ply, '${n.name}: leaf, score for side to move = $score');
    return score;
  }

  log(ply, '${n.name}: enter  window (alpha=$alpha, beta=$beta)');

  for (final child in n.children) {
    // Negamax: child sees the window flipped and negated.
    final eval = -search(child, ply + 1, !whiteToMove, -beta, -alpha);
    log(ply, '${n.name}: ${child.name} came back as $eval');

    if (prune && eval >= beta) {
      log(ply, '${n.name}: $eval >= beta($beta)  CUTOFF, skip remaining moves');
      return beta;
    }
    if (eval > alpha) {
      log(ply, '${n.name}: $eval > alpha($alpha)  alpha raised to $eval');
      alpha = eval;
    }
  }
  log(ply, '${n.name}: return $alpha');
  return alpha;
}

void main() {
  print('=== WITH alpha-beta ===');
  visited = 0;
  final a = search(tree, 0, true, -inf, inf);
  print('\nresult=$a  nodes visited=$visited\n');

  print('=== WITHOUT pruning ===');
  prune = false;
  verbose = false;
  visited = 0;
  // Without pruning, keep the window wide open so nothing is ever cut.
  final b = search(tree, 0, true, -inf, inf);
  print('result=$b  nodes visited=$visited');
}
