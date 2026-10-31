import 'dart:async';

import 'package:ace/components/board_view.dart';
import 'package:ace/online/online_game.dart';
import 'package:ace/online/online_game_backend.dart';
import 'package:ace/providers/online_game_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class OnlineGameScreen extends StatelessWidget {
  final OnlineGameBackend backend;
  final String userId;
  final OnlineGame game;

  const OnlineGameScreen({super.key, required this.backend, required this.userId, required this.game});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OnlineGameProvider>(
      create: (_) => OnlineGameProvider(backend: backend, userId: userId, game: game),
      child: const _OnlineGameView(),
    );
  }
}

class _OnlineGameView extends StatefulWidget {
  const _OnlineGameView();

  @override
  State<_OnlineGameView> createState() => _OnlineGameViewState();
}

class _OnlineGameViewState extends State<_OnlineGameView> {
  StreamSubscription<String>? _notices;
  bool _endDialogShown = false;

  @override
  void initState() {
    super.initState();
    _notices = context.read<OnlineGameProvider>().notices.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
  }

  static String describe(OnlineResult result, bool playerIsWhite) {
    final headline = result.isDraw ? 'Draw' : (result.whiteWon == playerIsWhite ? 'You win!' : 'You lose');
    return result.reason.isEmpty ? headline : '$headline – ${result.reason}';
  }

  String _status(OnlineGameProvider game) {
    final opponent = game.opponentName ?? 'Opponent';
    if (game.error != null) return game.error!;
    return switch (game.game.status) {
      OnlineGameStatus.waiting => 'Waiting for someone to join…',
      OnlineGameStatus.cancelled => 'Game cancelled',
      _ when game.result != null => describe(game.result!, game.playerIsWhite),
      _ when game.sending => 'Sending move…',
      _ when game.isHumanTurn => 'Your move',
      _ => '$opponent to move',
    };
  }

  void _showEndDialog(OnlineGameProvider game) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Game over'),
        content: Text(describe(game.result!, game.playerIsWhite)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('View board')),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).pop();
            },
            child: const Text('Back to lobby'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResign(OnlineGameProvider game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign?'),
        content: const Text('Your opponent will be awarded the win.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep playing')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Resign')),
        ],
      ),
    );
    if (confirmed == true) await game.resign();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<OnlineGameProvider>();
    final theme = Theme.of(context);
    final status = game.game.status;

    if (game.game.status == OnlineGameStatus.finished && game.result != null && !_endDialogShown) {
      _endDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEndDialog(game);
      });
    }

    final header = Row(
      children: [
        Expanded(child: Text(_status(game), style: theme.textTheme.titleMedium)),
        if (game.sending || (status == OnlineGameStatus.active && !game.isHumanTurn && game.result == null))
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == OnlineGameStatus.waiting) _WaitingCard(game: game),
        if (game.drawOfferedToMe && status == OnlineGameStatus.active) _DrawOfferCard(game: game),
        if (status == OnlineGameStatus.active) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: game.drawOfferedByMe || game.drawOfferedToMe ? null : game.offerDraw,
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(game.drawOfferedByMe ? 'Draw offered' : 'Offer draw'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmResign(game),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Resign'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (game.error != null) ...[
          OutlinedButton.icon(onPressed: game.refresh, icon: const Icon(Icons.sync_rounded), label: const Text('Resync')),
          const SizedBox(height: 16),
        ],
        _MoveList(san: game.sanHistory),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(status == OnlineGameStatus.waiting ? 'Online game' : 'vs ${game.opponentName ?? 'Opponent'}'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > constraints.maxHeight * 1.15;
            const padding = 16.0;

            if (wide) {
              final boardSize = (constraints.maxHeight - 2 * padding - 40).clamp(200.0, constraints.maxWidth * 0.6);
              return Padding(
                padding: const EdgeInsets.all(padding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: boardSize,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [header, const SizedBox(height: 12), BoardView(controller: game)],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: SingleChildScrollView(child: side)),
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
                  BoardView(controller: game),
                  const SizedBox(height: 16),
                  side,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  final OnlineGameProvider game;

  const _WaitingCard({required this.game});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = game.game.code;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Share this code with your opponent', textAlign: TextAlign.center, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SelectableText(
                code,
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 6),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        await game.cancel();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawOfferCard extends StatelessWidget {
  final OnlineGameProvider game;

  const _DrawOfferCard({required this.game});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text('${game.opponentName ?? 'Your opponent'} offers a draw')),
              TextButton(onPressed: () => game.answerDraw(false), child: const Text('Decline')),
              FilledButton(onPressed: () => game.answerDraw(true), child: const Text('Accept')),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoveList extends StatelessWidget {
  final List<String> san;

  const _MoveList({required this.san});

  @override
  Widget build(BuildContext context) {
    if (san.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (int i = 0; i < san.length; i += 2)
              Text(
                '${i ~/ 2 + 1}. ${san[i]}${i + 1 < san.length ? ' ${san[i + 1]}' : ''}',
                style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
          ],
        ),
      ),
    );
  }
}
