import 'package:ace/match/game_record.dart';
import 'package:ace/match/match_storage.dart';
import 'package:ace/match/report.dart';
import 'package:ace/match_ui/game_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class MatchResultsScreen extends StatefulWidget {
  final SavedMatch match;

  const MatchResultsScreen({super.key, required this.match});

  @override
  State<MatchResultsScreen> createState() => _MatchResultsScreenState();
}

class _MatchResultsScreenState extends State<MatchResultsScreen> {
  late final Future<List<GameRecord>> _games = widget.match.loadGames();
  late final Future<String> _report = widget.match.reportFile.readAsString();

  void _openGame(List<GameRecord> games, int gameNumber, int ply) {
    GameRecord? game = games.where((game) => game.gameNumber == gameNumber).firstOrNull;
    if (game == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameViewerScreen(game: game, initialPly: ply)));
  }

  @override
  Widget build(BuildContext context) {
    SavedMatch match = widget.match;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text("${match.config.engine1.label} vs ${match.config.engine2.label}"),
          actions: [
            IconButton(
              tooltip: "Share PGN and report",
              icon: const Icon(Icons.share),
              onPressed: () => SharePlus.instance.share(
                ShareParams(files: [XFile(match.pgnFile.path), XFile(match.reportFile.path)]),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: "Report"), Tab(text: "Suspicious"), Tab(text: "Games")]),
        ),
        body: FutureBuilder<List<GameRecord>>(
          future: _games,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text("Couldn't load games: ${snapshot.error}"));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            List<GameRecord> games = snapshot.data!;
            List<SuspiciousMove> suspicious = match.suspiciousMoves;

            return TabBarView(children: [
              FutureBuilder<String>(
                future: _report,
                builder: (context, report) => SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    report.data ?? "",
                    style: const TextStyle(fontFamily: "monospace", fontSize: 11),
                  ),
                ),
              ),
              suspicious.isEmpty
                  ? const Center(child: Text("Nothing flagged"))
                  : ListView.separated(
                      itemCount: suspicious.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        SuspiciousMove move = suspicious[index];
                        return ListTile(
                          title: Text("Game ${move.gameNumber}: ${move.moveText}  (${move.label})"),
                          subtitle: Text(move.explanation),
                          trailing: Text("-${move.winDrop}%"),
                          onTap: () => _openGame(games, move.gameNumber, move.ply),
                        );
                      },
                    ),
              ListView.separated(
                itemCount: games.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  GameRecord game = games[index];
                  int flagged = game.moves.where((move) => move.suspicion != null).length;
                  return ListTile(
                    dense: true,
                    title: Text("${game.gameNumber}. ${game.white.label} - ${game.black.label}   ${game.result}"),
                    subtitle: Text("${game.termination.description}, ${game.moves.length} plies"
                        "${flagged == 0 ? "" : ", $flagged flagged"}"),
                    onTap: () => _openGame(games, game.gameNumber, 0),
                  );
                },
              ),
            ]);
          },
        ),
      ),
    );
  }
}
