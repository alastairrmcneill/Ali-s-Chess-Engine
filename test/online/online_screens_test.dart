import 'package:ace/online/online_game.dart';
import 'package:ace/screens/online_game_screen.dart';
import 'package:ace/screens/online_lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'online_game_provider_test.dart' show FakeBackend, FakeServer, black, white;

void main() {
  testWidgets('lobby explains how to enable online play when Supabase is not configured', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnlineLobbyScreen()));
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });

  testWidgets('game screen shows whose move it is and updates when the opponent moves', (tester) async {
    final server = FakeServer();
    await tester.pumpWidget(MaterialApp(
      home: OnlineGameScreen(backend: FakeBackend(server, black), userId: black, game: server.game),
    ));
    expect(find.text('Alice to move'), findsOneWidget);
    expect(find.text('vs Alice'), findsOneWidget);

    await tester.runAsync(() async => server.update(moves: ['e2e4']));
    await tester.pump();
    expect(find.text('Your move'), findsOneWidget);
    expect(find.text('1. e4'), findsOneWidget);
  });

  testWidgets('waiting games show the join code', (tester) async {
    final server = FakeServer();
    server.game = OnlineGame.fromJson({
      'id': 'g1',
      'code': 'ABC123',
      'created_by': white,
      'white_id': white,
      'white_name': 'Alice',
      'status': 'waiting',
      'moves': <String>[],
      'updated_at': '2026-10-31T12:00:00Z',
    });
    await tester.pumpWidget(MaterialApp(
      home: OnlineGameScreen(backend: FakeBackend(server, white), userId: white, game: server.game),
    ));
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Waiting for someone to join…'), findsOneWidget);
  });
}
