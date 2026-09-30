import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/fen.dart';
import 'package:ace/chess_core/game_result.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/move_generator.dart';
import 'package:ace/chess_core/san.dart';
import 'package:ace/chess_core/uci.dart';
import 'package:ace/engines/chess_engine.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:ace/match/game_record.dart';
import 'package:ace/match/report.dart';

/// Called after every move with the new position, e.g. to show a live board
typedef MoveListener = void Function(String fen, String lastMoveUci);

/// Plays one game between two engines, with chess_core acting as referee.
///
/// The opening book moves are played first, then the engines alternate. Any move an engine returns is checked
/// against chess_core's legal moves; an illegal move, no move, or an exception loses the game for that engine.
Future<GameRecord> playGame({
  required int gameNumber,
  required int openingIndex,
  required List<String> openingMoves,
  required MatchPlayer white,
  required MatchPlayer black,
  int maxPlies = 500,
  MoveListener? onMove,
}) async {
  Map<String, ChessEngine> engines = {white.label: createEngine(white.engineId), black.label: createEngine(black.engineId)};
  for (ChessEngine engine in engines.values) {
    engine.newGame();
  }

  Board board = Board();
  MoveGenerator moveGenerator = MoveGenerator();
  List<MoveRecord> moves = [];
  List<String> uciMoves = [];

  GameRecord finish(String result, Termination termination, [String? detail]) {
    GameRecord record = GameRecord(
      gameNumber: gameNumber,
      openingIndex: openingIndex,
      white: white,
      black: black,
      moves: moves,
      result: result,
      termination: termination,
      terminationDetail: detail,
    );
    flagSuspiciousMoves(record);
    return record;
  }

  // Forced opening moves
  for (String uci in openingMoves) {
    Move move = Uci.toLegalMove(board, uci, moveGenerator) ?? (throw StateError("Illegal book move $uci"));
    moves.add(MoveRecord(uci: uci, san: San.fromMove(board, move), book: true));
    uciMoves.add(uci);
    board.makeMove(move);
    onMove?.call(board.toFen(), uci);
  }

  while (true) {
    Result result = GameResult.check(board, moveGenerator);
    if (result != Result.playing) {
      return finish(result.pgn, switch (result) {
        Result.whiteIsMated || Result.blackIsMated => Termination.checkmate,
        Result.stalemate => Termination.stalemate,
        Result.repetition => Termination.repetition,
        Result.fiftyMoveRule => Termination.fiftyMoveRule,
        _ => Termination.insufficientMaterial,
      });
    }
    if (moves.length >= maxPlies) return finish("1/2-1/2", Termination.maxLength, "$maxPlies plies");

    MatchPlayer mover = board.whiteToPlay ? white : black;
    String loss = board.whiteToPlay ? "0-1" : "1-0";

    SearchResult search;
    Stopwatch stopwatch = Stopwatch()..start();
    try {
      search = await engines[mover.label]!.search(
        EnginePosition(startFen: FenPosition.startingFen, uciMoves: List.of(uciMoves)),
        SearchLimits(moveTimeMs: mover.moveTimeMs),
      );
    } catch (error) {
      return finish(loss, Termination.engineError, "${mover.label}: $error");
    }
    stopwatch.stop();

    if (search.bestMove == null) return finish(loss, Termination.noMove, mover.label);
    Move? move = Uci.toLegalMove(board, search.bestMove!, moveGenerator);
    if (move == null) {
      return finish(loss, Termination.illegalMove, "${mover.label} played ${search.bestMove} in ${board.toFen()}");
    }

    moves.add(MoveRecord(
      uci: search.bestMove!,
      san: San.fromMove(board, move),
      scoreCp: search.scoreCp,
      mateIn: search.mateIn,
      depth: search.depth,
      nodes: search.nodes,
      timeMs: stopwatch.elapsedMilliseconds,
      pvSan: _pvToSan(board, search.pv),
    ));
    uciMoves.add(search.bestMove!);
    board.makeMove(move);
    onMove?.call(board.toFen(), search.bestMove!);
  }
}

/// Converts the engine's expected line to SAN, stopping at the first move that isn't legal
List<String> _pvToSan(Board board, List<String> pv) {
  List<String> sans = [];
  List<Move> played = [];
  for (String uci in pv) {
    Move? move = Uci.toLegalMove(board, uci);
    if (move == null) break;
    sans.add(San.fromMove(board, move));
    board.makeMove(move);
    played.add(move);
  }
  for (Move move in played.reversed) {
    board.unMakeMove(move);
  }
  return sans;
}
