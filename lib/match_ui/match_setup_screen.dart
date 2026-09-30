import 'dart:io';

import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match/match_runner.dart';
import 'package:ace/match_ui/match_live_screen.dart';
import 'package:ace/match_ui/saved_matches_screen.dart';
import 'package:flutter/material.dart';

class MatchSetupScreen extends StatefulWidget {
  const MatchSetupScreen({super.key});

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  String _engine1 = latestEngineId;
  String _engine2 = latestEngineId;
  final TextEditingController _games = TextEditingController(text: "1000");
  final TextEditingController _moveTime = TextEditingController(text: "100");
  final TextEditingController _moveTime2 = TextEditingController();
  late final TextEditingController _concurrency =
      TextEditingController(text: "${Platform.numberOfProcessors > 1 ? Platform.numberOfProcessors - 1 : 1}");

  int? _parse(TextEditingController controller) => int.tryParse(controller.text.trim());

  String get _estimate {
    int? games = _parse(_games);
    int? moveTime = _parse(_moveTime);
    int? concurrency = _parse(_concurrency);
    if (games == null || moveTime == null || concurrency == null || concurrency < 1) return "";
    int moveTime2 = _parse(_moveTime2) ?? moveTime;
    // v1 games average about 55 engine moves per side after the 16 book plies
    double seconds = games * 55 * (moveTime + moveTime2) / 1000 / concurrency;
    return "Rough estimate: ${(seconds / 60).ceil()} minutes";
  }

  void _start() {
    int? games = _parse(_games);
    int? moveTime = _parse(_moveTime);
    int? concurrency = _parse(_concurrency);
    if (games == null || moveTime == null || concurrency == null || games < 2 || moveTime < 1 || concurrency < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Check the numbers")));
      return;
    }
    MatchConfig config = MatchConfig(
      engine1Id: _engine1,
      engine2Id: _engine2,
      moveTimeMs: moveTime,
      engine2MoveTimeMs: _parse(_moveTime2),
      games: games,
      concurrency: concurrency,
    );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchLiveScreen(config: config)));
  }

  Widget _engineDropdown(String label, String value, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: [for (String id in engineRegistry.keys) DropdownMenuItem(value: id, child: Text(id))],
      onChanged: (id) => setState(() => onChanged(id!)),
    );
  }

  Widget _numberField(String label, TextEditingController controller, {String? hint}) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ACE Match Manager"),
        actions: [
          IconButton(
            tooltip: "Saved matches",
            icon: const Icon(Icons.folder_open),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedMatchesScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _engineDropdown("Engine 1", _engine1, (id) => _engine1 = id),
          _engineDropdown("Engine 2", _engine2, (id) => _engine2 = id),
          _numberField("Games (each opening is played twice, colours swapped)", _games),
          _numberField("Thinking time per move (ms)", _moveTime),
          _numberField("Engine 2 thinking time (ms, optional)", _moveTime2, hint: "Same as engine 1"),
          _numberField("Games at the same time", _concurrency),
          const SizedBox(height: 12),
          Text(_estimate, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            "Keep the app open while it runs; the screen stays on. Run with --release for full speed.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow), label: const Text("Start match")),
        ],
      ),
    );
  }
}
