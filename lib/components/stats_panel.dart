import 'package:ace/providers/game_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key});

  static String _count(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static String _eval(int? centipawns) {
    if (centipawns == null) return '';
    const mateThreshold = 900000000;
    if (centipawns.abs() >= mateThreshold) {
      final plies = 999999999 - centipawns.abs();
      return '${centipawns > 0 ? '+' : '-'}M${(plies + 1) ~/ 2}';
    }
    final pawns = centipawns / 100;
    return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final stats = game.stats;
    final theme = Theme.of(context);

    // Before the engine's first search there is nothing to show; after it, missing stats mean "not supported".
    final missing = game.searchesCompleted > 0 && stats == null ? 'n/a' : '–';

    String value(String? text) => text ?? missing;

    final eval = game.evalForWhite;

    final tiles = <(String, String)>[
      ('Depth', value(stats?.depth?.toString())),
      ('Eval (White)', value(eval == null ? null : _eval(eval))),
      ('Best move', value(stats?.bestMove)),
      ('Nodes', value(stats == null ? null : _count(stats.nodes))),
      ('Q-search nodes', value(stats == null ? null : _count(stats.qNodes))),
      ('Transpositions', value(stats == null ? null : _count(stats.transpositions))),
      ('Positions evaluated', value(stats == null ? null : _count(stats.evaluations))),
      ('Max Q depth', value(stats == null ? null : '${stats.maxQDepth} ply')),
    ];
    final iterations = game.iterations;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Engine search', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (game.engineThinking)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [for (final tile in tiles) SizedBox(width: width, child: _Tile(tile.$1, tile.$2))],
                );
              },
            ),
            if (stats != null && stats.pv.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Tile('Principal variation', stats.pv.join(' ')),
            ],
            if (iterations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Iterations', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              for (final i in iterations.reversed)
                Text(
                  'd${i.depth}  ${i.bestMove == null ? '-' : _eval(game.playerIsWhite ? -(i.eval ?? 0) : (i.eval ?? 0))}  '
                  '${i.bestMove ?? '-'}  ${i.elapsed.inMilliseconds}ms${i.aborted ? '  (aborted)' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;

  const _Tile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}
