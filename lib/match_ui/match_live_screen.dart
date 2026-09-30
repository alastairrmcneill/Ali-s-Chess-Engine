import 'dart:async';
import 'dart:io';

import 'package:ace/match/match_runner.dart';
import 'package:ace/match/match_stats.dart';
import 'package:ace/match/match_storage.dart';
import 'package:ace/match/report.dart';
import 'package:ace/match_ui/board_view.dart';
import 'package:ace/match_ui/match_results_screen.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Where matches played in the app are saved
Future<Directory> matchesDirectory() async {
  return Directory("${(await getApplicationDocumentsDirectory()).path}/matches");
}

class MatchLiveScreen extends StatefulWidget {
  final MatchConfig config;

  const MatchLiveScreen({super.key, required this.config});

  @override
  State<MatchLiveScreen> createState() => _MatchLiveScreenState();
}

class _MatchLiveScreenState extends State<MatchLiveScreen> {
  late final MatchRunner _runner = MatchRunner(widget.config);
  MatchRecorder? _recorder;
  MatchStats? _stats;
  LiveMove? _live;
  int _suspicious = 0;
  bool _finishing = false;
  String? _error;
  final Stopwatch _stopwatch = Stopwatch();
  final List<Future<void>> _pendingWrites = [];
  Timer? _ticker;

  MatchConfig get config => widget.config;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    WakelockPlus.enable();
    _recorder = await MatchRecorder.create(await matchesDirectory(), config);
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);

    _runner.events.listen(
      (event) {
        if (!mounted) return;
        if (event is GameFinished) {
          _pendingWrites.add(_recorder!.addGame(event.game));
          setState(() {
            _stats = MatchStats.fromGames(_runner.finishedGames, config.engine1.label, config.engine2.label);
            _suspicious = suspiciousCount(_runner.finishedGames);
          });
        } else if (event is LiveMove) {
          setState(() => _live = event);
        }
      },
      onError: (error) => mounted ? setState(() => _error = "$error") : null,
    );

    await _runner.run();
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    _stopwatch.stop();
    WakelockPlus.disable();
    await Future.wait(_pendingWrites);
    await _recorder!.finish(_runner.finishedGames, complete: _runner.isComplete);
    SavedMatch? saved = await SavedMatch.load(_recorder!.directory);
    if (mounted && saved != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MatchResultsScreen(match: saved)));
    }
  }

  @override
  void dispose() {
    // Leaving the screen stops the match; the games played so far are still saved
    _runner.stop();
    _ticker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  String _duration(Duration duration) {
    String two(int value) => value.toString().padLeft(2, "0");
    return "${duration.inHours}:${two(duration.inMinutes % 60)}:${two(duration.inSeconds % 60)}";
  }

  @override
  Widget build(BuildContext context) {
    int done = _runner.finishedGames.length;
    Duration elapsed = _stopwatch.elapsed;
    Duration? remaining = done == 0 ? null : elapsed * ((config.games - done) / done);
    MatchStats? stats = _stats;
    double? error = stats?.eloError95;
    TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text("${config.engine1.label} vs ${config.engine2.label}")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(value: done / config.games),
          const SizedBox(height: 8),
          Text("$done / ${config.games} games  ·  ${_duration(elapsed)} elapsed"
              "${remaining == null ? "" : "  ·  ~${_duration(remaining)} left"}"),
          const SizedBox(height: 16),
          if (stats != null) ...[
            Text("${config.engine1.label}: +${stats.wins} =${stats.draws} -${stats.losses}", style: text.titleMedium),
            Text(
              "Elo ${MatchStats.formatElo(stats.elo)}${error == null ? "" : " ± ${error.round()}"}"
              "  ·  score ${(stats.score * 100).toStringAsFixed(1)}%"
              "  ·  LOS ${(stats.los * 100).toStringAsFixed(1)}%",
            ),
            Text("Suspicious moves flagged: $_suspicious", style: text.bodySmall),
          ] else
            const Text("Waiting for the first game to finish..."),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
          if (_live != null) ...[
            Text("Game ${_live!.gameNumber}: ${_live!.whiteLabel} (white) vs ${_live!.blackLabel}",
                style: text.bodySmall),
            const SizedBox(height: 4),
            BoardView(fen: _live!.fen, lastMoveUci: _live!.lastMoveUci),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _finishing ? null : () => _runner.stop(),
            icon: const Icon(Icons.stop),
            label: const Text("Stop and save"),
          ),
        ],
      ),
    );
  }
}
