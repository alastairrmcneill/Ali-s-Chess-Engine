import 'dart:async';
import 'dart:isolate';

import 'package:ace/engines/chess_engine.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/game_runner.dart';
import 'package:ace/match/opening_book_data.dart';

class MatchConfig {
  final MatchPlayer engine1;
  final MatchPlayer engine2;
  final int games; // Always even: every opening is played twice with colours swapped
  final int concurrency; // Games played at the same time, one isolate each
  final int maxPlies; // Games longer than this are adjudicated as draws
  final int openingOffset; // First opening book line to use

  MatchConfig._({
    required this.engine1,
    required this.engine2,
    required this.games,
    required this.concurrency,
    required this.maxPlies,
    required this.openingOffset,
  });

  /// [engine2MoveTimeMs] defaults to [moveTimeMs]; giving engine 2 a different time is useful for sanity checks
  /// (the same engine with more time should win) or handicap matches.
  factory MatchConfig({
    required String engine1Id,
    required String engine2Id,
    int moveTimeMs = 100,
    int? engine2MoveTimeMs,
    int games = 1000,
    int concurrency = 1,
    int maxPlies = 500,
    int openingOffset = 0,
  }) {
    int time2 = engine2MoveTimeMs ?? moveTimeMs;
    String label1 = createEngine(engine1Id).name;
    String label2 = createEngine(engine2Id).name;
    if (moveTimeMs != time2) {
      label1 += " @${moveTimeMs}ms";
      label2 += " @${time2}ms";
    }
    if (label1 == label2) {
      label1 += " (1)";
      label2 += " (2)";
    }

    return MatchConfig._(
      engine1: MatchPlayer(engineId: engine1Id, moveTimeMs: moveTimeMs, label: label1),
      engine2: MatchPlayer(engineId: engine2Id, moveTimeMs: time2, label: label2),
      games: games < 2 ? 2 : games + games % 2,
      concurrency: concurrency < 1 ? 1 : concurrency,
      maxPlies: maxPlies,
      openingOffset: openingOffset,
    );
  }

  Map<String, dynamic> toJson() => {
        "engine1": engine1.toJson(),
        "engine2": engine2.toJson(),
        "games": games,
        "concurrency": concurrency,
        "maxPlies": maxPlies,
        "openingOffset": openingOffset,
      };

  factory MatchConfig.fromJson(Map<String, dynamic> json) => MatchConfig._(
        engine1: MatchPlayer.fromJson(json["engine1"]),
        engine2: MatchPlayer.fromJson(json["engine2"]),
        games: json["games"],
        concurrency: json["concurrency"],
        maxPlies: json["maxPlies"],
        openingOffset: json["openingOffset"] ?? 0,
      );
}

sealed class MatchEvent {}

class GameFinished extends MatchEvent {
  final GameRecord game;
  GameFinished(this.game);
}

/// A move in the featured game (always played on the first worker), for a live board
class LiveMove extends MatchEvent {
  final int gameNumber;
  final String whiteLabel;
  final String blackLabel;
  final String fen;
  final String lastMoveUci;
  LiveMove(this.gameNumber, this.whiteLabel, this.blackLabel, this.fen, this.lastMoveUci);
}

/// Plays a match between two engines on a pool of isolates, so the UI stays responsive and games run in parallel.
/// Both engines of a game run on the same isolate, so they get the same CPU share.
class MatchRunner {
  final MatchConfig config;
  final List<GameRecord> finishedGames = [];

  final StreamController<MatchEvent> _events = StreamController.broadcast();
  final List<Isolate> _isolates = [];
  final List<ReceivePort> _ports = [];
  final Completer<void> _done = Completer();
  late final List<Map<String, dynamic>> _jobs;
  int _nextJob = 0;
  bool _stopped = false;

  MatchRunner(this.config) {
    _jobs = [
      for (int game = 0; game < config.games; game++)
        {
          "gameNumber": game + 1,
          "openingIndex": (config.openingOffset + game ~/ 2) % openingBook.length,
          "white": (game.isEven ? config.engine1 : config.engine2).toJson(),
          "black": (game.isEven ? config.engine2 : config.engine1).toJson(),
          "maxPlies": config.maxPlies,
        }
    ];
  }

  Stream<MatchEvent> get events => _events.stream;
  bool get isStopped => _stopped;
  bool get isComplete => finishedGames.length == config.games;

  /// Starts the workers. The returned future completes when every game is finished or [stop] is called.
  Future<void> run() async {
    int workers = config.concurrency < config.games ? config.concurrency : config.games;
    for (int worker = 0; worker < workers && !_stopped; worker++) {
      ReceivePort port = ReceivePort();
      _ports.add(port);
      port.listen((message) => _onMessage(message, worker));
      Isolate isolate = await Isolate.spawn(_workerMain, [port.sendPort, worker == 0], onError: port.sendPort);
      _isolates.add(isolate);
      if (_stopped) isolate.kill(priority: Isolate.immediate); // stop() was called while this one was starting
    }
    return _done.future;
  }

  void _onMessage(Object? message, int worker) {
    if (_stopped) return;
    if (message is! Map) {
      // Uncaught error inside a worker (Isolate.spawn's onError sends [error, stackTrace])
      _events.addError(StateError("Match worker $worker failed: $message"));
      _finish();
      return;
    }
    switch (message["type"]) {
      case "ready":
        _sendNextJob(message["port"] as SendPort);
      case "move":
        _events.add(LiveMove(message["gameNumber"], message["white"], message["black"], message["fen"], message["uci"]));
      case "result":
        GameRecord game = GameRecord.fromJson((message["game"] as Map).cast<String, dynamic>());
        finishedGames.add(game);
        _events.add(GameFinished(game));
        if (isComplete) {
          _finish();
        } else {
          _sendNextJob(message["port"] as SendPort);
        }
    }
  }

  void _sendNextJob(SendPort worker) {
    if (_nextJob < _jobs.length) {
      Map<String, dynamic> job = _jobs[_nextJob++];
      int openingIndex = job["openingIndex"];
      worker.send({...job, "openingMoves": openingBook[openingIndex].split(" ")});
    } else {
      worker.send("exit");
    }
  }

  /// Stops immediately. Games already finished are kept; games in progress are discarded.
  void stop() {
    if (_stopped) return;
    _finish();
  }

  void _finish() {
    _stopped = true;
    for (Isolate isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    for (ReceivePort port in _ports) {
      port.close();
    }
    if (!_done.isCompleted) _done.complete();
    _events.close();
  }
}

// Worker isolate: receives game jobs one at a time and sends back finished games.
void _workerMain(List<Object> args) {
  SendPort toMain = args[0] as SendPort;
  bool featured = args[1] as bool;
  ReceivePort inbox = ReceivePort();
  Set<String> warmedUp = {};
  toMain.send({"type": "ready", "port": inbox.sendPort});

  inbox.listen((message) async {
    if (message == "exit") {
      inbox.close();
      return;
    }
    Map job = message as Map;
    MatchPlayer white = MatchPlayer.fromJson((job["white"] as Map).cast<String, dynamic>());
    MatchPlayer black = MatchPlayer.fromJson((job["black"] as Map).cast<String, dynamic>());

    // A fresh isolate runs slowly until the code has been compiled, which would handicap whichever engine moves
    // first. Warm each engine up once so that cost never lands on a real move.
    for (String engineId in {white.engineId, black.engineId}) {
      if (warmedUp.add(engineId)) {
        await createEngine(engineId).search(const EnginePosition(), const SearchLimits(moveTimeMs: 200));
      }
    }
    GameRecord game = await playGame(
      gameNumber: job["gameNumber"],
      openingIndex: job["openingIndex"],
      openingMoves: (job["openingMoves"] as List).cast<String>(),
      white: white,
      black: black,
      maxPlies: job["maxPlies"],
      onMove: featured
          ? (fen, uci) => toMain.send({
                "type": "move",
                "gameNumber": job["gameNumber"],
                "white": white.label,
                "black": black.label,
                "fen": fen,
                "uci": uci,
              })
          : null,
    );
    toMain.send({"type": "result", "game": game.toJson(), "port": inbox.sendPort});
  });
}
