import 'dart:async';
import 'dart:isolate';

import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';

/// Runs one engine in its own isolate so the UI never freezes while it thinks. The engine's search is
/// synchronous and blocks the isolate, so it pushes a [SearchStats] after every iterative deepening step and
/// the worker forwards each one straight to [stats].
class EngineWorker {
  final ReceivePort _receive;
  final Completer<void> _ready = Completer<void>();
  final StreamController<SearchStats> _stats = StreamController<SearchStats>.broadcast();
  late final Isolate _isolate;
  late final SendPort _send;
  Completer<EngineMoveResult>? _pending;
  bool _disposed = false;

  EngineWorker._(this._receive);

  /// One event per completed (or aborted) iterative deepening step of the search in progress.
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
      case 'iteration':
        if (!_stats.isClosed) _stats.add(SearchStats.fromJson(data[1] as Map));
      case 'result':
        _pending?.complete(EngineMoveResult(
          uciMove: data[1] as String,
          evaluation: data[2] as int?,
          depth: data[3] as int?,
          nodes: data[4] as int?,
          principalVariation: data[5] == null ? null : List<String>.from(data[5] as List),
        ));
        _pending = null;
      case 'error':
        _pending?.completeError(StateError(data[1] as String));
        _pending = null;
    }
  }

  static void _entry(List<Object> args) {
    final toMain = args[0] as SendPort;
    final engine = EngineRegistry.create(args[1] as String);

    final commands = ReceivePort();
    toMain.send(commands.sendPort);
    engine.newGame();

    commands.listen((dynamic message) {
      final command = message as List<dynamic>;
      if (command[0] != 'search') return;

      try {
        final result = engine.getMove(
          command[1] as String,
          List<String>.from(command[2] as List),
          SearchLimits(moveTime: Duration(milliseconds: command[3] as int)),
          onIteration: (iteration) => toMain.send(['iteration', iteration.toJson()]),
        );
        toMain.send([
          'result',
          result.uciMove,
          result.evaluation,
          result.depth,
          result.nodes,
          result.principalVariation,
        ]);
      } catch (e) {
        toMain.send(['error', e.toString()]);
      }
    });
  }
}
