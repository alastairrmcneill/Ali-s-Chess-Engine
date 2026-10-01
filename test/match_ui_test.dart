import 'package:ace/engines/engine_registry.dart';
import 'package:ace/main_match.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match_ui/game_viewer_screen.dart';
import 'package:ace/match_ui/inspector_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GameRecord sampleGame() => GameRecord(
      gameNumber: 3,
      openingIndex: 1,
      white: const MatchPlayer(engineId: "v1", moveTimeMs: 50, label: "ACE v1 (1)"),
      black: const MatchPlayer(engineId: "v1", moveTimeMs: 50, label: "ACE v1 (2)"),
      moves: [
        MoveRecord(uci: "e2e4", san: "e4", book: true),
        MoveRecord(uci: "e7e5", san: "e5", book: true),
        MoveRecord(uci: "d1h5", san: "Qh5", scoreCp: 40, depth: 3, nodes: 900, timeMs: 51, pvSan: ["Qh5", "Nc6"]),
        MoveRecord(
            uci: "b8c6", san: "Nc6", scoreCp: 20, depth: 3, timeMs: 50, suspicion: "eval fell from +0.20 to -9.00"),
        MoveRecord(uci: "f1c4", san: "Bc4", scoreCp: 60, depth: 3, timeMs: 50),
        MoveRecord(uci: "g8f6", san: "Nf6", scoreCp: -40, depth: 3, timeMs: 50),
        MoveRecord(uci: "h5f7", san: "Qxf7#", mateIn: 1, depth: 3, timeMs: 50),
      ],
      result: "1-0",
      termination: Termination.checkmate,
    );

void main() {
  testWidgets("match setup screen lists engines and starts empty", (tester) async {
    await tester.pumpWidget(const MatchManagerApp());
    expect(find.text("ACE Match Manager"), findsOneWidget);
    expect(find.text(latestEngineId), findsNWidgets(2)); // Both engines default to the latest version
    expect(find.text("Start match"), findsOneWidget);
  });

  testWidgets("game viewer steps through moves and shows engine info", (tester) async {
    // Phone shaped screen so the text under the board is built
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: GameViewerScreen(game: sampleGame(), initialPly: 3)));
    expect(find.text("Next: 2... Nc6 by ACE v1 (2)"), findsOneWidget);
    expect(find.textContaining("eval fell from +0.20 to -9.00"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.last_page));
    await tester.pump();
    expect(find.text("Result 1-0: checkmate"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.first_page));
    await tester.pump();
    expect(find.text("Opening book move"), findsOneWidget);
  });

  testWidgets("inspector panel ranks moves on a background isolate", (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: InspectorPanel(
          startFen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1",
          uciMoves: [],
          playedUci: "a1a2",
          defaultEngineId: "v1",
        ),
      ),
    ));

    // The default 300ms per move would be slow here, pick 100ms
    await tester.tap(find.text("300"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("100").last);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Analyse"));
    await tester.runAsync(() async {
      for (int i = 0; i < 300 && find.textContaining("Ra8#").evaluate().isEmpty; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pump();

    expect(find.text("Ra8#   #1"), findsOneWidget); // Mate in one ranked first
    expect(find.textContaining("← played"), findsOneWidget); // The played move is shown even outside the top 5
  });
}
