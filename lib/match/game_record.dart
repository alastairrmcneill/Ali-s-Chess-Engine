import 'package:ace/chess_core/board.dart';
import 'package:ace/chess_core/fen.dart';
import 'package:ace/chess_core/move.dart';
import 'package:ace/chess_core/san.dart';
import 'package:ace/match/pgn.dart';

/// One side of a match: which engine version and how long it may think per move
class MatchPlayer {
  final String engineId;
  final int moveTimeMs;
  final String label; // Shown in PGNs and reports, unique within a match

  const MatchPlayer({required this.engineId, required this.moveTimeMs, required this.label});

  Map<String, dynamic> toJson() => {"engineId": engineId, "moveTimeMs": moveTimeMs, "label": label};

  factory MatchPlayer.fromJson(Map<String, dynamic> json) =>
      MatchPlayer(engineId: json["engineId"], moveTimeMs: json["moveTimeMs"], label: json["label"]);
}

enum Termination {
  checkmate,
  stalemate,
  repetition,
  fiftyMoveRule,
  insufficientMaterial,
  maxLength, // Adjudicated as a draw after too many plies
  illegalMove, // Engine returned a move that isn't legal: it loses
  noMove, // Engine returned no move: it loses
  engineError, // Engine threw an exception: it loses
}

extension TerminationInfo on Termination {
  String get description => switch (this) {
        Termination.checkmate => "checkmate",
        Termination.stalemate => "stalemate",
        Termination.repetition => "threefold repetition",
        Termination.fiftyMoveRule => "fifty move rule",
        Termination.insufficientMaterial => "insufficient material",
        Termination.maxLength => "max game length (adjudicated draw)",
        Termination.illegalMove => "illegal move",
        Termination.noMove => "engine returned no move",
        Termination.engineError => "engine error",
      };

  /// Standard PGN Termination tag value
  String get pgnTag => switch (this) {
        Termination.maxLength => "adjudication",
        Termination.illegalMove || Termination.noMove || Termination.engineError => "rules infraction",
        _ => "normal",
      };
}

class MoveRecord {
  final String uci;
  final String san;
  final bool book; // Forced opening book move, not chosen by an engine

  // What the engine reported when choosing this move (null for book moves)
  final int? scoreCp;
  final int? mateIn;
  final int? depth;
  final int? nodes;
  final int? timeMs;
  final List<String> pvSan;

  /// Set when the report flags this move as a likely mistake, with a short explanation
  String? suspicion;

  MoveRecord({
    required this.uci,
    required this.san,
    this.book = false,
    this.scoreCp,
    this.mateIn,
    this.depth,
    this.nodes,
    this.timeMs,
    this.pvSan = const [],
    this.suspicion,
  });

  /// Score from the mover's point of view in centipawns, with mates mapped to +/- 100000
  int? get comparableScore {
    if (mateIn != null) return mateIn! > 0 ? 100000 - mateIn! : -100000 - mateIn!;
    return scoreCp;
  }

  String get scoreText {
    if (mateIn != null) return "#$mateIn";
    if (scoreCp == null) return "?";
    String pawns = (scoreCp!.abs() / 100).toStringAsFixed(2);
    return scoreCp! < 0 ? "-$pawns" : "+$pawns";
  }

  /// PGN comment, e.g. "+0.45/7 98ms 41230 nodes; pv: Nf3 Nc6 Bb5"
  String get comment {
    if (book) return "book";
    String text = "$scoreText/${depth ?? "?"} ${timeMs ?? 0}ms";
    if (nodes != null) text += " $nodes nodes";
    if (pvSan.isNotEmpty) text += "; pv: ${pvSan.join(" ")}";
    if (suspicion != null) text += "; ? $suspicion";
    return text;
  }

  static final RegExp _commentPattern =
      RegExp(r"^(#-?\d+|[+-]\d+\.\d+|\?)/(\d+|\?) (\d+)ms(?: (\d+) nodes)?(?:; pv: ([^;]*))?(?:; \? (.*))?$");

  factory MoveRecord.fromPgn(String uci, PgnMove pgnMove) {
    String? comment = pgnMove.comment;
    if (comment == "book") return MoveRecord(uci: uci, san: pgnMove.san, book: true);

    Match? match = comment == null ? null : _commentPattern.firstMatch(comment);
    if (match == null) return MoveRecord(uci: uci, san: pgnMove.san);

    String score = match.group(1)!;
    return MoveRecord(
      uci: uci,
      san: pgnMove.san,
      scoreCp: score.startsWith("#") || score == "?" ? null : (double.parse(score) * 100).round(),
      mateIn: score.startsWith("#") ? int.parse(score.substring(1)) : null,
      depth: int.tryParse(match.group(2)!),
      timeMs: int.parse(match.group(3)!),
      nodes: match.group(4) == null ? null : int.parse(match.group(4)!),
      pvSan: match.group(5)?.trim().split(" ").where((san) => san.isNotEmpty).toList() ?? const [],
      suspicion: match.group(6),
    );
  }

  Map<String, dynamic> toJson() => {
        "uci": uci,
        "san": san,
        if (book) "book": true,
        if (scoreCp != null) "scoreCp": scoreCp,
        if (mateIn != null) "mateIn": mateIn,
        if (depth != null) "depth": depth,
        if (nodes != null) "nodes": nodes,
        if (timeMs != null) "timeMs": timeMs,
        if (pvSan.isNotEmpty) "pv": pvSan,
        if (suspicion != null) "suspicion": suspicion,
      };

  factory MoveRecord.fromJson(Map<String, dynamic> json) => MoveRecord(
        uci: json["uci"],
        san: json["san"],
        book: json["book"] ?? false,
        scoreCp: json["scoreCp"],
        mateIn: json["mateIn"],
        depth: json["depth"],
        nodes: json["nodes"],
        timeMs: json["timeMs"],
        pvSan: (json["pv"] as List?)?.cast<String>() ?? const [],
        suspicion: json["suspicion"],
      );
}

class GameRecord {
  final int gameNumber; // 1-based, games 2n-1 and 2n share an opening with colours swapped
  final int openingIndex;
  final MatchPlayer white;
  final MatchPlayer black;
  final String startFen;
  final List<MoveRecord> moves;
  final String result; // "1-0", "0-1" or "1/2-1/2"
  final Termination termination;
  final String? terminationDetail; // e.g. the illegal move that was played

  GameRecord({
    required this.gameNumber,
    required this.openingIndex,
    required this.white,
    required this.black,
    this.startFen = FenPosition.startingFen,
    required this.moves,
    required this.result,
    required this.termination,
    this.terminationDetail,
  });

  /// Points scored by the player with [label] (1, 0.5 or 0)
  double scoreFor(String label) {
    if (result == "1/2-1/2") return 0.5;
    bool whiteWon = result == "1-0";
    return (label == white.label) == whiteWon ? 1 : 0;
  }

  /// Label of the player who moved at [ply] (0-based index into [moves])
  MatchPlayer moverAt(int ply) {
    bool whiteStarts = startFen.split(" ")[1] == "w";
    return (ply % 2 == 0) == whiteStarts ? white : black;
  }

  /// FEN of the position before each move, plus the final position at the end
  List<String> positions() {
    Board board = Board.fromFen(startFen);
    List<String> fens = [board.toFen()];
    for (MoveRecord record in moves) {
      Move? move = San.toLegalMove(board, record.san);
      if (move == null) break;
      board.makeMove(move);
      fens.add(board.toFen());
    }
    return fens;
  }

  PgnGame toPgnGame({String event = "ACE engine match", String? date}) {
    return PgnGame({
      "Event": event,
      "Site": "ACE match manager",
      "Date": date ?? "????.??.??",
      "Round": "$gameNumber",
      "White": white.label,
      "Black": black.label,
      "Result": result,
      if (startFen != FenPosition.startingFen) ...{"SetUp": "1", "FEN": startFen},
      "WhiteEngine": white.engineId,
      "BlackEngine": black.engineId,
      "WhiteMoveTime": "${white.moveTimeMs}",
      "BlackMoveTime": "${black.moveTimeMs}",
      "Opening": "book #${openingIndex + 1}",
      "Termination": termination.pgnTag,
      "TerminationDetails": terminationDetail == null
          ? termination.description
          : "${termination.description}: $terminationDetail",
      "PlyCount": "${moves.length}",
    }, [
      for (MoveRecord move in moves) PgnMove(move.san, comment: move.comment, nags: move.suspicion == null ? [] : [2]),
    ]);
  }

  /// Rebuilds a game written by [toPgnGame]
  factory GameRecord.fromPgnGame(PgnGame game) {
    Map<String, String> headers = game.headers;
    String startFen = headers["FEN"] ?? FenPosition.startingFen;
    Board board = Board.fromFen(startFen);
    List<MoveRecord> moves = [];
    for (PgnMove pgnMove in game.moves) {
      Move? move = San.toLegalMove(board, pgnMove.san);
      if (move == null) break;
      moves.add(MoveRecord.fromPgn(move.toChessNotation(), pgnMove));
      board.makeMove(move);
    }

    String details = headers["TerminationDetails"] ?? "";
    Termination termination = Termination.values.firstWhere(
      (termination) => details.startsWith(termination.description),
      orElse: () => Termination.checkmate,
    );
    String? detail = details.contains(": ") ? details.substring(details.indexOf(": ") + 2) : null;

    return GameRecord(
      gameNumber: int.tryParse(headers["Round"] ?? "") ?? 0,
      openingIndex: (int.tryParse((headers["Opening"] ?? "").replaceAll("book #", "")) ?? 1) - 1,
      white: MatchPlayer(
        engineId: headers["WhiteEngine"] ?? "?",
        moveTimeMs: int.tryParse(headers["WhiteMoveTime"] ?? "") ?? 0,
        label: headers["White"] ?? "White",
      ),
      black: MatchPlayer(
        engineId: headers["BlackEngine"] ?? "?",
        moveTimeMs: int.tryParse(headers["BlackMoveTime"] ?? "") ?? 0,
        label: headers["Black"] ?? "Black",
      ),
      startFen: startFen,
      moves: moves,
      result: game.result,
      termination: termination,
      terminationDetail: detail,
    );
  }

  Map<String, dynamic> toJson() => {
        "gameNumber": gameNumber,
        "openingIndex": openingIndex,
        "white": white.toJson(),
        "black": black.toJson(),
        "startFen": startFen,
        "moves": moves.map((move) => move.toJson()).toList(),
        "result": result,
        "termination": termination.name,
        if (terminationDetail != null) "terminationDetail": terminationDetail,
      };

  factory GameRecord.fromJson(Map<String, dynamic> json) => GameRecord(
        gameNumber: json["gameNumber"],
        openingIndex: json["openingIndex"],
        white: MatchPlayer.fromJson(json["white"]),
        black: MatchPlayer.fromJson(json["black"]),
        startFen: json["startFen"],
        moves: (json["moves"] as List).map((move) => MoveRecord.fromJson(move)).toList(),
        result: json["result"],
        termination: Termination.values.byName(json["termination"]),
        terminationDetail: json["terminationDetail"],
      );
}
