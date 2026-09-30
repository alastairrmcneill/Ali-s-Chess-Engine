import 'package:ace/match/match_storage.dart';
import 'package:ace/match_ui/match_live_screen.dart';
import 'package:ace/match_ui/match_results_screen.dart';
import 'package:flutter/material.dart';

class SavedMatchesScreen extends StatelessWidget {
  const SavedMatchesScreen({super.key});

  Future<List<SavedMatch>> _load() async => SavedMatch.list(await matchesDirectory());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Saved matches")),
      body: FutureBuilder<List<SavedMatch>>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          List<SavedMatch> matches = snapshot.data!;
          if (matches.isEmpty) return const Center(child: Text("No matches yet"));

          return ListView.separated(
            itemCount: matches.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              SavedMatch match = matches[index];
              String date = match.startedAt.toString().substring(0, 16);
              return ListTile(
                title: Text("${match.config.engine1.label} vs ${match.config.engine2.label}"),
                subtitle: Text("${match.summaryLine}\n$date${match.complete ? "" : "  (stopped early)"}"),
                isThreeLine: true,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => MatchResultsScreen(match: match))),
              );
            },
          );
        },
      ),
    );
  }
}
