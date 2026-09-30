import 'dart:async';
import 'dart:isolate';

import 'package:ace/analysis/position_inspector.dart';

/// Runs [PositionInspector.analyse] on a background isolate so the UI stays responsive.
/// Progress is reported through [onProgress]; the returned future completes with all moves, best first.
Future<List<CandidateMove>> analyseInBackground({
  required String engineId,
  required String startFen,
  required List<String> uciMoves,
  required int msPerCandidate,
  void Function(int done, int total)? onProgress,
}) async {
  ReceivePort port = ReceivePort();
  Completer<List<CandidateMove>> result = Completer();

  port.listen((message) {
    if (message is Map && message["type"] == "progress") {
      onProgress?.call(message["done"], message["total"]);
    } else if (message is Map && message["type"] == "result") {
      result.complete((message["candidates"] as List)
          .map((json) => CandidateMove.fromJson((json as Map).cast<String, dynamic>()))
          .toList());
      port.close();
    } else if (!result.isCompleted) {
      result.completeError(StateError("Inspector failed: $message"));
      port.close();
    }
  });

  await Isolate.spawn(
    _inspectorMain,
    {
      "port": port.sendPort,
      "engineId": engineId,
      "startFen": startFen,
      "uciMoves": uciMoves,
      "msPerCandidate": msPerCandidate,
    },
    onError: port.sendPort,
  );
  return result.future;
}

Future<void> _inspectorMain(Map<String, dynamic> job) async {
  SendPort port = job["port"];
  List<CandidateMove> candidates = await PositionInspector.analyse(
    engineId: job["engineId"],
    startFen: job["startFen"],
    uciMoves: (job["uciMoves"] as List).cast<String>(),
    msPerCandidate: job["msPerCandidate"],
    onProgress: (done, total) => port.send({"type": "progress", "done": done, "total": total}),
  );
  port.send({"type": "result", "candidates": candidates.map((candidate) => candidate.toJson()).toList()});
}
