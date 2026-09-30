import 'package:ace/analysis/inspector_isolate.dart';
import 'package:ace/analysis/position_inspector.dart';
import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/san.dart';
import 'package:ace/chess_core/uci.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match_ui/board_view.dart';
import 'package:flutter/material.dart';

/// Asks an engine version for its top moves in a position (runs on a background isolate)
class InspectorPanel extends StatefulWidget {
  final String startFen;
  final List<String> uciMoves;
  final String? playedUci; // The move actually played in the game, highlighted in the results
  final String defaultEngineId;

  const InspectorPanel({
    super.key,
    required this.startFen,
    required this.uciMoves,
    this.playedUci,
    required this.defaultEngineId,
  });

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  late String _engineId =
      engineRegistry.containsKey(widget.defaultEngineId) ? widget.defaultEngineId : latestEngineId;
  int _msPerCandidate = 300;
  int _topN = 5;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  List<CandidateMove>? _candidates;
  String? _error;

  Future<void> _analyse() async {
    setState(() {
      _running = true;
      _candidates = null;
      _error = null;
      _done = 0;
    });
    try {
      List<CandidateMove> candidates = await analyseInBackground(
        engineId: _engineId,
        startFen: widget.startFen,
        uciMoves: widget.uciMoves,
        msPerCandidate: _msPerCandidate,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
      );
      if (mounted) setState(() => _candidates = candidates);
    } catch (error) {
      if (mounted) setState(() => _error = "$error");
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Shows the position at the end of a candidate's expected line
  void _preview(CandidateMove candidate) {
    Board board = Board.fromFen(widget.startFen);
    for (String uci in widget.uciMoves) {
      board.makeMove(Uci.toLegalMove(board, uci)!);
    }
    String? lastUci;
    for (String san in candidate.lineSan) {
      Move? move = San.toLegalMove(board, san);
      if (move == null) break;
      lastUci = move.toChessNotation();
      board.makeMove(move);
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${candidate.san}  ${candidate.scoreText}"),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BoardView(fen: board.toFen(), lastMoveUci: lastUci),
            const SizedBox(height: 8),
            Text(candidate.lineSan.join(" ")),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Top moves", style: text.titleMedium),
            Row(children: [
              const Text("Engine "),
              DropdownButton<String>(
                value: _engineId,
                items: [for (String id in engineRegistry.keys) DropdownMenuItem(value: id, child: Text(id))],
                onChanged: _running ? null : (id) => setState(() => _engineId = id!),
              ),
              const Spacer(),
              const Text("ms/move "),
              DropdownButton<int>(
                value: _msPerCandidate,
                items: [for (int ms in const [100, 300, 1000, 3000]) DropdownMenuItem(value: ms, child: Text("$ms"))],
                onChanged: _running ? null : (ms) => setState(() => _msPerCandidate = ms!),
              ),
              const Spacer(),
              const Text("Top "),
              DropdownButton<int>(
                value: _topN,
                items: [for (int n in const [3, 5, 10, 100]) DropdownMenuItem(value: n, child: Text(n == 100 ? "all" : "$n"))],
                onChanged: (n) => setState(() => _topN = n!),
              ),
            ]),
            FilledButton(onPressed: _running ? null : _analyse, child: const Text("Analyse")),
            if (_running) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
              Text("$_done / $_total moves", style: text.bodySmall),
            ],
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_candidates != null)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (int i = 0; i < _candidates!.length && i < _topN; i++) _candidateTile(i, _candidates![i]),
                    ..._playedTileIfHidden(),
                    Text("Scores are from the moving side's point of view. Tap a move to see its line.",
                        style: text.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _candidateTile(int rank, CandidateMove candidate) {
    bool played = candidate.uci == widget.playedUci;
    return ListTile(
      dense: true,
      leading: Text("${rank + 1}."),
      title: Text("${candidate.san}   ${candidate.scoreText}${played ? "   ← played" : ""}",
          style: TextStyle(fontWeight: played ? FontWeight.bold : null)),
      subtitle: Text(candidate.note ?? "depth ${candidate.depth ?? "-"}: ${candidate.lineSan.join(" ")}",
          maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => _preview(candidate),
    );
  }

  List<Widget> _playedTileIfHidden() {
    int rank = _candidates!.indexWhere((candidate) => candidate.uci == widget.playedUci);
    if (rank < _topN) return [];
    return [const Divider(), _candidateTile(rank, _candidates![rank])];
  }
}
