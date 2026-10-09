import 'package:ace/chess_core/game_end.dart';
import 'package:ace/components/board_view.dart';
import 'package:ace/components/stats_panel.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameProvider _game;
  int? _dialogShownForGeneration;

  @override
  void initState() {
    super.initState();
    _game = context.read<GameProvider>();
  }

  @override
  void dispose() {
    _game.endGame();
    super.dispose();
  }

  static String describe(GameEnd end, bool playerIsWhite) {
    final playerWon = (end.outcome == GameOutcome.whiteWin) == playerIsWhite;
    final headline = switch (end.outcome) {
      GameOutcome.draw => 'Draw',
      _ => playerWon ? 'You win!' : 'You lose',
    };
    final reason = switch (end.termination) {
      GameTermination.checkmate => 'by checkmate',
      GameTermination.stalemate => 'by stalemate',
      GameTermination.threefoldRepetition => 'by threefold repetition',
      GameTermination.fiftyMoveRule => 'by the fifty-move rule',
      GameTermination.insufficientMaterial => 'by insufficient material',
      GameTermination.maxMoves => 'by move limit',
      GameTermination.illegalMove => 'the engine played an illegal move',
      GameTermination.engineError => 'the engine crashed',
    };
    return '$headline – $reason';
  }

  void _showEndDialog(GameProvider game) {
    final end = game.gameEnd!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Game over'),
        content: Text(describe(end, game.playerIsWhite) +
            (end.detail == null ? '' : '\n${end.detail}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('View board')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).pop();
            },
            child: const Text('Home'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              game.restart();
            },
            child: const Text('Rematch'),
          ),
        ],
      ),
    );
  }

  void _showMenu(GameProvider game) {
    showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Game menu'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(context).pop();
              game.restart();
            },
            child: const ListTile(
                leading: Icon(Icons.refresh_rounded),
                title: Text('Restart match')),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).pop();
            },
            child: const ListTile(
                leading: Icon(Icons.home_rounded), title: Text('Exit to home')),
          ),
        ],
      ),
    );
  }

  String _status(GameProvider game) {
    final end = game.gameEnd;
    if (end != null) return describe(end, game.playerIsWhite);
    if (game.engineThinking) return 'Engine is thinking…';
    return 'Your move';
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final settings = game.settings;
    final theme = Theme.of(context);

    if (game.gameEnd != null && _dialogShownForGeneration != game.generation) {
      _dialogShownForGeneration = game.generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEndDialog(game);
      });
    }

    final header = Row(
      children: [
        Expanded(
          child: Text(_status(game), style: theme.textTheme.titleMedium),
        ),
        if (game.engineThinking)
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(settings == null
            ? 'ACE'
            : '${settings.engineName} · ${settings.depth != null ? 'depth ${settings.depth}' : '${(settings.moveTime.inMilliseconds / 1000).toStringAsFixed(1)} s'}'),
        actions: [
          IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => _showMenu(game),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > constraints.maxHeight * 1.15;
            const padding = 16.0;

            if (wide) {
              final boardSize = (constraints.maxHeight - 2 * padding - 40)
                  .clamp(200.0, constraints.maxWidth * 0.6);
              return Padding(
                padding: const EdgeInsets.all(padding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: boardSize,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          const SizedBox(height: 12),
                          const BoardView()
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    const Expanded(
                        child: SingleChildScrollView(child: StatsPanel())),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 12),
                  const BoardView(),
                  const SizedBox(height: 16),
                  const StatsPanel(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
