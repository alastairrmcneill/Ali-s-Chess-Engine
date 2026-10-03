import 'dart:async';
import 'dart:isolate';

import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';

/// Runs one engine in its own isolate so the UI never freezes while it thinks, and streams the engine's
/// search counters back while it searches. The engine code itself is untouched: the isolate just polls
/// [LiveStatsEngine.liveStats] on a timer (the engines yield to the event loop during search, so it fires).
class EngineWorker {
  static const Duration _statsInterval = Duration(milliseconds: 50);

  final ReceivePort _receive;
  final Completer<void> _ready = Completer<void>();
  final StreamController<SearchStats> _stats = StreamController<SearchStats>.broadcast();
  late final Isolate _isolate;
  late final SendPort _send;
  Completer<EngineMoveResult>? _pending;
  bool _disposed = false;

  EngineWorker._(this._receive);

  /// Live stats for the search in progress, roughly every [_statsInterval], plus one final snapshot.
  Stream<SearchStats> get stats => _stats.stream;

  static Future<EngineWorker> spawn(String engineId) async {
    final receive = ReceivePort();
    final worker = EngineWorker._(receive);
    receive.listen(worker._onMessage);
    worker._isolate = await Isolate.spawn(_entry, [receive.sendPort, engineId]);
    await worker._ready.future;
    return worker;
  }

  Future<EngineMoveResult> search(String startFen, List<String> uciMoves, Duration moveTime) {
    final pending = _pending = Completer<EngineMoveResult>();
    _send.send(['search', startFen, uciMoves, moveTime.inMilliseconds]);
    return pending.future;
  }

  /// Kills the isolate, aborting any search in progress. A pending [search] future never completes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate.kill(priority: Isolate.immediate);
    _receive.close();
    _stats.close();
    _pending = null;
  }

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _send = message;
      _ready.complete();
      return;
    }
    final data = message as List<dynamic>;
    switch (data[0] as String) {
      case 'stats':
        if (!_stats.isClosed) _stats.add(_decodeStats(data));
      case 'result':
        _pending?.complete(EngineMoveResult(
          uciMove: data[1] as String,
          evaluation: data[2] as int?,
          depth: data[3] as int?,
          nodes: data[4] as int?,
        ));
        _pending = null;
      case 'error':
        _pending?.completeError(StateError(data[1] as String));
        _pending = null;
    }
  }

  static List<Object?> _encodeStats(SearchStats s) => [
        'stats',
        s.depth,
        s.nodes,
        s.qNodes,
        s.transpositions,
        s.maxQDepth,
        s.evaluations,
        s.eval,
        s.bestMove,
        s.elapsed.inMicroseconds,
      ];

  static SearchStats _decodeStats(List<dynamic> d) => SearchStats(
        depth: d[1] as int?,
        nodes: d[2] as int,
        qNodes: d[3] as int,
        transpositions: d[4] as int,
        maxQDepth: d[5] as int,
        evaluations: d[6] as int,
        eval: d[7] as int?,
        bestMove: d[8] as String?,
        elapsed: Duration(microseconds: d[9] as int),
      );

  static final RegExp _depthLine = RegExp(r'Starting with search of depth (\d+)');

  static void _entry(List<Object> args) {
    final toMain = args[0] as SendPort;
    final engine = EngineRegistry.create(args[1] as String);
    int? currentDepth;

    // The engines print their iterative deepening progress. The depth isn't exposed any other way, so read it
    // from there (and keep the engines' debug prints out of the console).
    runZoned(
      () {
        final commands = ReceivePort();
        toMain.send(commands.sendPort);
        engine.newGame();

        commands.listen((dynamic message) async {
          final command = message as List<dynamic>;
          if (command[0] != 'search') return;

          currentDepth = null;
          final stopwatch = Stopwatch()..start();
          SearchStats? snapshot() => engine is LiveStatsEngine
              ? (engine as LiveStatsEngine).liveStats?.copyWith(depth: currentDepth, elapsed: stopwatch.elapsed)
              : null;

          final timer = Timer.periodic(_statsInterval, (_) {
            final stats = snapshot();
            if (stats != null) toMain.send(_encodeStats(stats));
          });

          try {
            final result = await engine.getMove(
              command[1] as String,
              List<String>.from(command[2] as List),
              SearchLimits(moveTime: Duration(milliseconds: command[3] as int)),
            );
            timer.cancel();
            final stats = snapshot();
            if (stats != null) toMain.send(_encodeStats(stats));
            toMain.send(['result', result.uciMove, result.evaluation, result.depth, result.nodes]);
          } catch (e) {
            timer.cancel();
            toMain.send(['error', e.toString()]);
          }
        });
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          final match = _depthLine.firstMatch(line);
          if (match != null) currentDepth = int.parse(match.group(1)!);
        },
      ),
    );
  }
}
