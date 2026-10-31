import 'dart:async';

import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/online/online_game.dart';
import 'package:ace/online/online_game_backend.dart';
import 'package:ace/providers/online_game_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const white = 'white-user';
const black = 'black-user';

/// A single shared game held in memory, standing in for the Supabase table and its functions.
class FakeServer {
  OnlineGame game;
  final _updates = StreamController<OnlineGame?>.broadcast();
  int _clock = 0;

  FakeServer()
      : game = OnlineGame(
          id: 'g1',
          code: 'ABC123',
          createdBy: white,
          whiteId: white,
          blackId: black,
          whiteName: 'Alice',
          blackName: 'Bob',
          status: OnlineGameStatus.active,
          moves: const [],
          updatedAt: DateTime(2026),
        );

  void update({List<String>? moves, OnlineGameStatus? status, String? result, String? termination, String? draw, bool clearDraw = false}) {
    game = OnlineGame(
      id: game.id,
      code: game.code,
      createdBy: game.createdBy,
      whiteId: game.whiteId,
      blackId: game.blackId,
      whiteName: game.whiteName,
      blackName: game.blackName,
      status: status ?? game.status,
      moves: moves ?? game.moves,
      result: result ?? game.result,
      termination: termination ?? game.termination,
      drawOfferedBy: clearDraw ? null : draw ?? game.drawOfferedBy,
      updatedAt: DateTime(2026).add(Duration(seconds: ++_clock)),
    );
    _updates.add(game);
  }
}

class FakeBackend implements OnlineGameBackend {
  final FakeServer server;
  final String userId;

  FakeBackend(this.server, this.userId);

  @override
  Future<String> ensureSignedIn() async => userId;

  @override
  Future<OnlineGame> fetchGame(String gameId) async => server.game;

  @override
  Future<OnlineGame> playMove(String gameId, {required String uci, required int ply, String? result, String? termination}) async {
    final game = server.game;
    if (ply != game.moves.length) throw const OnlineGameException('Out of sync');
    if ((ply.isEven ? game.whiteId : game.blackId) != userId) throw const OnlineGameException('Not your turn');
    server.update(
      moves: [...game.moves, uci],
      clearDraw: true,
      status: result == null ? null : OnlineGameStatus.finished,
      result: result,
      termination: termination,
    );
    return server.game;
  }

  @override
  Future<OnlineGame> resign(String gameId) async {
    server.update(
      status: OnlineGameStatus.finished,
      result: userId == white ? '0-1' : '1-0',
      termination: 'resignation',
    );
    return server.game;
  }

  @override
  Future<OnlineGame> offerDraw(String gameId) async {
    server.update(draw: userId);
    return server.game;
  }

  @override
  Future<OnlineGame> answerDraw(String gameId, {required bool accept}) async {
    server.update(
      clearDraw: true,
      status: accept ? OnlineGameStatus.finished : null,
      result: accept ? '1/2-1/2' : null,
      termination: accept ? 'agreement' : null,
    );
    return server.game;
  }

  @override
  Stream<OnlineGame?> watch(String gameId) => server._updates.stream;

  @override
  Future<OnlineGame> createGame({required String name, required String side}) => throw UnimplementedError();
  @override
  Future<OnlineGame> joinGame({required String code, required String name}) => throw UnimplementedError();
  @override
  Future<List<OnlineGame>> myOpenGames() async => [];
  @override
  Future<OnlineGame> cancel(String gameId) => throw UnimplementedError();
}

Move findMove(OnlineGameProvider game, String uci) {
  final from = BoardHelper.squareIndex(uci.substring(0, 2));
  final to = BoardHelper.squareIndex(uci.substring(2, 4));
  return game.movesBetween(from, to).first;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeServer server;
  late OnlineGameProvider alice;
  late OnlineGameProvider bob;

  setUp(() {
    server = FakeServer();
    alice = OnlineGameProvider(backend: FakeBackend(server, white), userId: white, game: server.game);
    bob = OnlineGameProvider(backend: FakeBackend(server, black), userId: black, game: server.game);
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  test('sides and turns follow the server game', () {
    expect(alice.playerIsWhite, isTrue);
    expect(bob.playerIsWhite, isFalse);
    expect(alice.isHumanTurn, isTrue);
    expect(bob.isHumanTurn, isFalse);
    expect(alice.opponentName, 'Bob');
    expect(bob.opponentName, 'Alice');
  });

  test('a move reaches the opponent and hands them the turn', () async {
    alice.playHumanMove(findMove(alice, 'e2e4'));
    expect(alice.isHumanTurn, isFalse);
    await settle();

    expect(server.game.moves, ['e2e4']);
    expect(bob.sanHistory, ['e4']);
    expect(bob.isHumanTurn, isTrue);
    expect(bob.lastMove?.targetSquare, BoardHelper.squareIndex('e4'));
    expect(alice.isHumanTurn, isFalse);
  });

  test('checkmate is reported to the server with the move', () async {
    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      final mover = server.game.moves.length.isEven ? alice : bob;
      mover.playHumanMove(findMove(mover, uci));
      await settle();
    }

    expect(server.game.status, OnlineGameStatus.finished);
    expect(server.game.result, '0-1');
    expect(server.game.termination, 'checkmate');
    expect(alice.result?.reason, 'by checkmate');
    expect(alice.isHumanTurn, isFalse);
  });

  test('an illegal move from the server is refused', () async {
    server.update(moves: ['e2e5']);
    await settle();

    expect(bob.error, contains('illegal'));
    expect(bob.isHumanTurn, isFalse);
    expect(bob.sanHistory, isEmpty);
  });

  test('a rejected move is rolled back to the server position', () async {
    // Another client already played for white.
    server.game = OnlineGame.fromJson({
      'id': 'g1',
      'code': 'ABC123',
      'created_by': white,
      'white_id': white,
      'black_id': black,
      'status': 'active',
      'moves': ['d2d4'],
      'updated_at': DateTime(2027).toIso8601String(),
    });
    final notices = <String>[];
    alice.notices.listen(notices.add);

    alice.playHumanMove(findMove(alice, 'e2e4'));
    await settle();
    await settle();

    expect(notices, ['Out of sync']);
    expect(alice.sanHistory, ['d4']);
    expect(alice.isHumanTurn, isFalse);
  });

  test('stale updates do not undo newer state', () async {
    alice.playHumanMove(findMove(alice, 'e2e4'));
    await settle();
    final newer = server.game;

    alice.offerDraw();
    await settle();
    expect(bob.drawOfferedToMe, isTrue);

    // Replay an older snapshot as if it arrived late.
    server._updates.add(newer);
    await settle();
    expect(bob.drawOfferedToMe, isTrue);
  });

  test('draw offers can be accepted', () async {
    await alice.offerDraw();
    await settle();
    expect(alice.drawOfferedByMe, isTrue);
    expect(bob.drawOfferedToMe, isTrue);

    await bob.answerDraw(true);
    await settle();
    expect(alice.result?.isDraw, isTrue);
    expect(alice.result?.reason, 'by agreement');
  });

  test('resigning gives the opponent the win', () async {
    await bob.resign();
    await settle();
    expect(alice.result?.whiteWon, isTrue);
    expect(alice.result?.reason, 'by resignation');
    expect(alice.isFinished, isTrue);
  });

  test('parses a row from Supabase', () {
    final game = OnlineGame.fromJson({
      'id': 'id',
      'code': 'XYZ789',
      'created_by': 'u1',
      'white_id': 'u1',
      'black_id': null,
      'white_name': 'Ali',
      'black_name': null,
      'status': 'waiting',
      'moves': <dynamic>[],
      'result': null,
      'termination': null,
      'draw_offered_by': null,
      'created_at': '2026-10-31T12:00:00.000000+00:00',
      'updated_at': '2026-10-31T12:00:00.000000+00:00',
    });
    expect(game.status, OnlineGameStatus.waiting);
    expect(game.isWhite('u1'), isTrue);
    expect(game.opponentName('u1'), isNull);
  });
}
