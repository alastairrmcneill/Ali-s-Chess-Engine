import 'dart:async';

import 'package:ace/online/online_game.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server side of online games. Abstract so tests can run games without Supabase.
abstract class OnlineGameBackend {
  /// Signs in (anonymously if needed) and returns the current user's id.
  Future<String> ensureSignedIn();

  Future<OnlineGame> createGame({required String name, required String side});
  Future<OnlineGame> joinGame({required String code, required String name});
  Future<OnlineGame> fetchGame(String gameId);

  /// The current user's games that are waiting for an opponent or still being played, newest first.
  Future<List<OnlineGame>> myOpenGames();
  Future<OnlineGame> playMove(String gameId, {required String uci, required int ply, String? result, String? termination});
  Future<OnlineGame> resign(String gameId);
  Future<OnlineGame> offerDraw(String gameId);
  Future<OnlineGame> answerDraw(String gameId, {required bool accept});
  Future<OnlineGame> cancel(String gameId);

  /// Every change to the game, plus `null` whenever the live connection is (re)established so the caller can
  /// refetch anything it missed while disconnected.
  Stream<OnlineGame?> watch(String gameId);
}

class SupabaseOnlineGameBackend implements OnlineGameBackend {
  final SupabaseClient _client;

  SupabaseOnlineGameBackend([SupabaseClient? client]) : _client = client ?? Supabase.instance.client;

  @override
  Future<String> ensureSignedIn() async {
    final user = _client.auth.currentUser ?? (await _client.auth.signInAnonymously()).user;
    if (user == null) throw StateError('Could not sign in');
    return user.id;
  }

  Future<OnlineGame> _rpc(String function, Map<String, dynamic> params) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(function, params: params);
      return OnlineGame.fromJson(row);
    } on PostgrestException catch (e) {
      throw OnlineGameException(e.message);
    }
  }

  @override
  Future<OnlineGame> createGame({required String name, required String side}) =>
      _rpc('create_online_game', {'p_name': name, 'p_side': side});

  @override
  Future<OnlineGame> joinGame({required String code, required String name}) =>
      _rpc('join_online_game', {'p_code': code, 'p_name': name});

  @override
  Future<OnlineGame> fetchGame(String gameId) async {
    final row = await _client.from('online_games').select().eq('id', gameId).single();
    return OnlineGame.fromJson(row);
  }

  @override
  Future<List<OnlineGame>> myOpenGames() async {
    final rows = await _client
        .from('online_games')
        .select()
        .inFilter('status', ['waiting', 'active'])
        .order('updated_at', ascending: false)
        .limit(20);
    return rows.map(OnlineGame.fromJson).toList();
  }

  @override
  Future<OnlineGame> playMove(String gameId, {required String uci, required int ply, String? result, String? termination}) =>
      _rpc('play_online_move', {
        'p_game_id': gameId,
        'p_uci': uci,
        'p_ply': ply,
        'p_result': result,
        'p_termination': termination,
      });

  @override
  Future<OnlineGame> resign(String gameId) => _rpc('resign_online_game', {'p_game_id': gameId});

  @override
  Future<OnlineGame> offerDraw(String gameId) => _rpc('offer_online_draw', {'p_game_id': gameId});

  @override
  Future<OnlineGame> answerDraw(String gameId, {required bool accept}) =>
      _rpc('answer_online_draw', {'p_game_id': gameId, 'p_accept': accept});

  @override
  Future<OnlineGame> cancel(String gameId) => _rpc('cancel_online_game', {'p_game_id': gameId});

  @override
  Stream<OnlineGame?> watch(String gameId) {
    late final StreamController<OnlineGame?> controller;
    RealtimeChannel? channel;

    controller = StreamController<OnlineGame?>(
      onListen: () {
        channel = _client
            .channel('online_game:$gameId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'online_games',
              filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
              callback: (payload) => controller.add(OnlineGame.fromJson(payload.newRecord)),
            )
            .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) controller.add(null);
        });
      },
      onCancel: () async {
        final c = channel;
        if (c != null) await _client.removeChannel(c);
      },
    );
    return controller.stream;
  }
}

class OnlineGameException implements Exception {
  final String message;

  const OnlineGameException(this.message);

  @override
  String toString() => message;
}
