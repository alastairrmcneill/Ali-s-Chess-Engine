import 'dart:math';

import 'package:ace/engines/engine_registry.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:ace/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _SideChoice { white, black, random }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _engineId = EngineRegistry.latestId;
  double _seconds = 1.0;
  _SideChoice _side = _SideChoice.white;
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);

    final playerIsWhite = switch (_side) {
      _SideChoice.white => true,
      _SideChoice.black => false,
      _SideChoice.random => Random().nextBool(),
    };
    final game = context.read<GameProvider>();
    await game.startGame(GameSettings(
      engineId: _engineId,
      moveTime: Duration(milliseconds: (_seconds * 1000).round()),
      playerIsWhite: playerIsWhite,
    ));

    if (!mounted) return;
    setState(() => _starting = false);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GameScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.psychology_alt_rounded, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'ACE',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 4),
                  ),
                  Text(
                    "Ali's Chess Engine",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 40),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label(theme, 'Opponent'),
                          DropdownButtonFormField<String>(
                            initialValue: _engineId,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: [
                              for (final id in EngineRegistry.allIds)
                                DropdownMenuItem(value: id, child: Text(EngineRegistry.create(id).displayName)),
                            ],
                            onChanged: (id) => setState(() => _engineId = id ?? _engineId),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(child: _label(theme, 'Thinking time')),
                              Text('${_seconds.toStringAsFixed(1)} s', style: theme.textTheme.titleSmall),
                            ],
                          ),
                          Slider(
                            value: _seconds,
                            min: 0.1,
                            max: 5.0,
                            divisions: 49,
                            onChanged: (v) => setState(() => _seconds = double.parse(v.toStringAsFixed(1))),
                          ),
                          const SizedBox(height: 12),
                          _label(theme, 'Play as'),
                          SegmentedButton<_SideChoice>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: _SideChoice.white, label: Text('White')),
                              ButtonSegment(value: _SideChoice.black, label: Text('Black')),
                              ButtonSegment(value: _SideChoice.random, label: Text('Random')),
                            ],
                            selected: {_side},
                            onSelectionChanged: (s) => setState(() => _side = s.first),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _starting ? null : _start,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('New game', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
}
