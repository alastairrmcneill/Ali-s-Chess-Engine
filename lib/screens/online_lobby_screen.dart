import 'package:ace/online/online_game.dart';
import 'package:ace/online/online_game_backend.dart';
import 'package:ace/online/supabase_config.dart';
import 'package:ace/screens/online_game_screen.dart';
import 'package:flutter/material.dart';

enum _Side { white, black, random }

class OnlineLobbyScreen extends StatefulWidget {
  /// Defaults to Supabase; tests pass a fake.
  final OnlineGameBackend? backend;

  const OnlineLobbyScreen({super.key, this.backend});

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  OnlineGameBackend? _backend;
  final _nameController = TextEditingController(text: 'Player');
  final _codeController = TextEditingController();
  _Side _side = _Side.random;
  String? _userId;
  List<OnlineGame> _openGames = [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.backend != null || SupabaseConfig.isConfigured) {
      _backend = widget.backend ?? SupabaseOnlineGameBackend();
      _connect();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _connect() => _run(() async {
        _userId = await _backend!.ensureSignedIn();
        _openGames = await _backend!.myOpenGames();
      });

  /// Runs [action] with the buttons disabled, showing any failure.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  String get _name {
    final name = _nameController.text.trim();
    return name.isEmpty ? 'Player' : name;
  }

  Future<void> _open(OnlineGame game) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OnlineGameScreen(backend: _backend!, userId: _userId!, game: game),
    ));
    if (mounted) await _run(() async => _openGames = await _backend!.myOpenGames());
  }

  Future<void> _create() async {
    OnlineGame? game;
    await _run(() async => game = await _backend!.createGame(name: _name, side: _side.name));
    if (game != null && mounted) await _open(game!);
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    OnlineGame? game;
    await _run(() async => game = await _backend!.joinGame(code: code, name: _name));
    if (game != null && mounted) await _open(game!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Play online')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _backend == null ? _notConfigured(theme) : _lobby(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notConfigured(ThemeData theme) => Text(
        'Online play isn\'t set up in this build. Run the app with '
        '--dart-define=SUPABASE_URL=… and --dart-define=SUPABASE_PUBLISHABLE_KEY=…',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge,
      );

  Widget _lobby(ThemeData theme) {
    final ready = !_busy && _userId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
          if (_userId == null) OutlinedButton(onPressed: _busy ? null : _connect, child: const Text('Retry')),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(theme, 'Your name'),
                TextField(
                  controller: _nameController,
                  maxLength: 24,
                  decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ''),
                ),
                const SizedBox(height: 24),
                _label(theme, 'Play as'),
                SegmentedButton<_Side>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Side.white, label: Text('White')),
                    ButtonSegment(value: _Side.black, label: Text('Black')),
                    ButtonSegment(value: _Side.random, label: Text('Random')),
                  ],
                  selected: {_side},
                  onSelectionChanged: (s) => setState(() => _side = s.first),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: ready ? _create : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Create game'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(theme, 'Join a friend\'s game'),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Game code'),
                  onSubmitted: (_) => ready ? _join() : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: ready ? _join : null,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Join'),
                ),
              ],
            ),
          ),
        ),
        if (_openGames.isNotEmpty) ...[
          const SizedBox(height: 24),
          _label(theme, 'Your games'),
          for (final game in _openGames)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(game.isWhite(_userId!) ? Icons.circle_outlined : Icons.circle),
              title: Text(game.status == OnlineGameStatus.waiting
                  ? 'Waiting for opponent · ${game.code}'
                  : 'vs ${game.opponentName(_userId!) ?? 'Opponent'}'),
              subtitle: Text('${game.moves.length} moves played'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: ready ? () => _open(game) : null,
            ),
        ],
        if (_busy) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
}
