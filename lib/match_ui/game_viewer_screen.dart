import 'package:ace/match/game_record.dart';
import 'package:ace/match/report.dart';
import 'package:ace/match_ui/board_view.dart';
import 'package:ace/match_ui/inspector_panel.dart';
import 'package:flutter/material.dart';

/// Steps through a match game. The board shows the position *before* the selected move, together with what the
/// engine reported when it chose that move, so a suspicious move can be inspected straight away.
class GameViewerScreen extends StatefulWidget {
  final GameRecord game;
  final int initialPly;

  const GameViewerScreen({super.key, required this.game, this.initialPly = 0});

  @override
  State<GameViewerScreen> createState() => _GameViewerScreenState();
}

class _GameViewerScreenState extends State<GameViewerScreen> {
  late final List<String> _positions = widget.game.positions();
  late int _ply = widget.initialPly.clamp(0, widget.game.moves.length);

  GameRecord get game => widget.game;

  void _goTo(int ply) => setState(() => _ply = ply.clamp(0, game.moves.length));

  void _inspect() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => InspectorPanel(
        startFen: game.startFen,
        uciMoves: game.moves.take(_ply).map((move) => move.uci).toList(),
        playedUci: _ply < game.moves.length ? game.moves[_ply].uci : null,
        defaultEngineId: _ply < game.moves.length ? game.moverAt(_ply).engineId : game.white.engineId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TextTheme text = Theme.of(context).textTheme;
    MoveRecord? selected = _ply < game.moves.length ? game.moves[_ply] : null;

    return Scaffold(
      appBar: AppBar(title: Text("Game ${game.gameNumber}: ${game.white.label} - ${game.black.label}")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          BoardView(fen: _positions[_ply], lastMoveUci: _ply > 0 ? game.moves[_ply - 1].uci : null),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(onPressed: () => _goTo(0), icon: const Icon(Icons.first_page)),
              IconButton(onPressed: () => _goTo(_ply - 1), icon: const Icon(Icons.chevron_left)),
              IconButton(onPressed: () => _goTo(_ply + 1), icon: const Icon(Icons.chevron_right)),
              IconButton(onPressed: () => _goTo(game.moves.length), icon: const Icon(Icons.last_page)),
              const SizedBox(width: 8),
              if (selected != null)
                FilledButton.tonalIcon(onPressed: _inspect, icon: const Icon(Icons.search), label: const Text("Inspect")),
            ],
          ),
          if (selected != null) ...[
            Text("Next: ${moveText(game, _ply)} by ${game.moverAt(_ply).label}", style: text.titleSmall),
            Text(selected.book ? "Opening book move" : selected.comment, style: text.bodySmall),
          ] else
            Text("Result ${game.result}: ${game.termination.description}"
                "${game.terminationDetail == null ? "" : " (${game.terminationDetail})"}"),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (int ply = 0; ply < game.moves.length; ply++)
                ChoiceChip(
                  label: Text(
                    "${ply.isEven ? "${ply ~/ 2 + 1}. " : ""}${game.moves[ply].san}"
                    "${game.moves[ply].suspicion != null ? "?" : ""}",
                    style: TextStyle(
                      fontSize: 12,
                      color: game.moves[ply].suspicion != null
                          ? Theme.of(context).colorScheme.error
                          : game.moves[ply].book
                              ? Theme.of(context).disabledColor
                              : null,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                  selected: ply == _ply,
                  onSelected: (_) => _goTo(ply),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
