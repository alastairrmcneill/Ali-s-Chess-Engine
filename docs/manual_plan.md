# Match Manager — Implementation Plan

A step-by-step plan for building an engine-vs-engine **match manager** for ACE, freezing
engine versions so `v2` can be tested against `v1` (and `v3` against both), and letting the app
user pick which version to play against.

This is written for you to implement yourself. Each phase lists the files to create, the classes
and method signatures, the key logic, the tests to write, and a **Done when…** checklist. Do the
phases in order. Each one builds on the last and ends with something you can run or test.

---

## 0. Decisions (from our Q&A)

| Topic                  | Decision                                                                                                                                                   |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Where matches run      | **Command line only** (`dart run bin/match.dart …`) on your laptop                                                                                         |
| App                    | Player can **choose which engine version** to play against                                                                                                 |
| Versioning             | **Snapshot folders**: `lib/engines/v1/`, `lib/engines/v2/`, … Each one is fully self-contained and frozen once superseded                                  |
| Engine protocol        | In-process Dart interface that only speaks **strings**: start FEN + list of UCI moves in, UCI move out                                                     |
| Time control           | **Fixed time per move**, set per match with `--movetime`                                                                                                   |
| Openings               | **Your existing PGN file**, read by your own PGN/SAN parser. Each position is played **twice with colours swapped**                                        |
| Third-party chess code | **None.** The referee, SAN and PGN handling are all written by you (only `args` is used, for CLI flags)                                                    |
| Match size             | **Fixed 1000 games, run in series** (parallel play is a side note at the end)                                                                              |
| Termination            | Normal chess rules, plus **illegal move / crash / no move = loss (logged)**, plus **draw after 300 moves** (600 plies)                                     |
| Output                 | W/D/L, Elo ± error, score by colour, PGN of every game, average depth/nodes/time per engine, termination breakdown, error log                              |
| Bug fixes              | **v1 is frozen exactly as it is today** (a true baseline). The known bugs are listed in §11 and fixing them is **v2**, which is your first real experiment |

---

## 1. The big picture

```
                 ┌───────────────────────────── bin/match.dart (CLI) ─────────────────────────────┐
                 │  parses args → MatchConfig → MatchRunner.run() → writes results folder        │
                 └───────────────────────────────────────┬────────────────────────────────────────┘
                                                         │
   OpeningBook ── List<String> FENs ──►  MatchRunner ────┼──► GameRunner.playGame(white, black, fen)
   (reads PGN)                          (schedules 1000  │        │
                                         games, colour   │        │  loop:
                                         swap, stats)    │        │   referee.checkGameEnd()?
                                                         │        │   engine.getMove(startFen, uciMoves, limits)
                                                         │        │   referee.tryPlayUci(move)  ← illegal ⇒ loss
                                                         │        ▼
                                                         │   GameRecord ──► MatchStats (W/D/L, Elo)
                                                         │              ──► PgnWriter  (games.pgn)
                                                         │              ──► error log
                                                         ▼
                ChessEngine (interface)  ◄── implemented by ──  lib/engines/v1/adapter.dart  (wraps frozen v1)
                                                                lib/engines/v2/adapter.dart  (wraps v2)
                                                                lib/engines/random/…         (sanity checks)

                Referee (lib/referee/): the neutral judge, built from YOUR code: a frozen, perft-tested copy of
                the rules core + your own game-end and SAN logic. It is used by the match manager AND by the app,
                so neither depends on any engine version's code. No third-party chess packages.
```

### Three rules that keep this sane

1. **A snapshot folder only imports `dart:*` and files inside its own folder.** The one exception is
   `adapter.dart`, which may also import `lib/engines/engine_interface.dart`. A test enforces this
   (Phase 1).
2. **Nothing outside a snapshot ever touches its `Board`/`Move` types.** Everything crosses the
   boundary as strings (FEN and UCI like `e2e4`, `e7e8q`, `e1g1`).
3. **The referee is separate from every engine.** It has its own frozen copy of the rules code that
   no engine version touches. If `v2`'s move generator gets a bug, the referee catches it as an
   illegal move. If the referee used v2's code, both would agree on the wrong answer.

### Target folder layout (when everything is done)

```
bin/
  match.dart                         # CLI entry point
tool/
  snapshot_engine.dart               # copies lib/engines/vN → lib/engines/vM and rewrites imports
match_data/
  openings.pgn                       # your opening file
match_results/                       # output (git-ignored)
lib/
  engines/
    engine_interface.dart            # ChessEngine, SearchLimits, EngineMoveResult
    engine_registry.dart             # 'v1' → factory, 'v2' → factory, 'random' → factory
    random/random_engine.dart        # plays random legal moves (sanity baseline)
    v1/
      adapter.dart                   # AceEngine implements ChessEngine
      ai/ core/ helpers/ extensions/ # frozen copy of today's lib/chess_engine + lib/extensions
    v2/ …                            # same shape
  referee/
    rules/                           # frozen copy of the rules core (core/ helpers/ extensions/, no ai/)
    referee.dart                     # Referee class
    san.dart                         # SAN writer + parser (for PGN in and out)
    game_end.dart                    # GameTermination enum, GameOutcome enum, GameEnd class
  match_manager/
    match_config.dart
    pgn_reader.dart                  # splits/tokenises PGN text (headers, comments, variations…)
    opening_book.dart
    game_record.dart
    game_runner.dart
    match_runner.dart
    match_stats.dart
    elo.dart
    pgn_writer.dart
    match_output.dart
  components/
    GUI.dart  square.dart  piece_image.dart   # piece_image.dart is new (Phase 0)
  providers/game_provider.dart       # rewritten in Phase 9 to use Referee + ChessEngine
test/
  engines/  referee/  match_manager/  helpers/fake_engines.dart  fixtures/openings_sample.pgn
```

`lib/chess_engine/` and `lib/tests/` are deleted at the end of Phase 9, once the app no longer uses them.

---

## Phase 0: Preparation

Goal: a clean baseline, the new dependencies, and engine code that can run **without Flutter**.

### 0.1 Baseline

- [ ] Run `flutter test` and confirm `test/perft_test.dart` passes. Note how long it takes.
- [ ] Commit anything outstanding so the snapshot in Phase 1 is a known commit. Tag it:
      `git tag engine-v1`.

### 0.2 Why Flutter has to be removed from the engine

`dart run bin/match.dart` runs on the plain Dart VM, which **cannot load `package:flutter`**
(there's no `dart:ui`). Right now there's exactly one Flutter import inside the engine:

- `lib/chess_engine/core/piece.dart` imports `package:flutter/material.dart` only for
  `static Widget getImg(int piece)`.

Fix (a pure move, no behaviour change):

1. Create `lib/components/piece_image.dart`:

   ```dart
   import 'package:ace/chess_engine/core/piece.dart';
   import 'package:flutter/material.dart';

   class PieceImage {
     static Widget forPiece(int piece) { /* body moved verbatim from Piece.getImg */ }
   }
   ```

2. Delete `getImg` and the Flutter import from `piece.dart`.
3. In `lib/components/square.dart`, replace the 3 calls `Piece.getImg(piece)` → `PieceImage.forPiece(piece)`.
4. Run the app once to check pieces still render. Run `flutter test`.

Do this **before** the Phase 1 snapshot, so v1 is born Flutter-free.

### 0.3 Dependencies

Add to `pubspec.yaml` under `dependencies:`:

```yaml
args: ^2.4.2 # CLI argument parsing (optional: parse `List<String> args` by hand if you prefer)
```

Then run `flutter pub get`. **No chess packages.** Rules, SAN and PGN are all your own code (Phase 2–3).

### 0.4 Housekeeping

- [ ] Add `match_results/` to `.gitignore`.
- [ ] Create empty folders `bin/ tool/ match_data/ lib/engines/ lib/referee/ lib/match_manager/`.
- [ ] Copy your opening PGN into `match_data/openings.pgn`.

**Done when:** the app runs, `flutter test` passes, and `grep -r "package:flutter" lib/chess_engine` returns nothing.

---

## Phase 1: Engine interface and the v1 snapshot

### 1.1 `lib/engines/engine_interface.dart`

```dart
/// Limits for a single search. Fixed time per move for now.
class SearchLimits {
  final Duration moveTime;
  const SearchLimits({required this.moveTime});
}

/// What an engine returns for one move.
class EngineMoveResult {
  final String uciMove;      // e.g. "e2e4", "e7e8q", "e1g1". Lowercase.
  final int? eval;           // from the side-to-move's point of view, engine units (null if unknown)
  final int? depth;          // deepest *completed* iterative-deepening depth (null if unknown)
  final int? nodes;          // nodes searched (null if unknown)
  const EngineMoveResult(this.uciMove, {this.eval, this.depth, this.nodes});
}

abstract class ChessEngine {
  /// Short id used on the CLI and in the app picker, e.g. "v1".
  String get id;

  /// Human-readable, e.g. "ACE v1". Used in PGN headers.
  String get displayName;

  /// Called before every game. Clear transposition tables, history, etc.
  Future<void> newGame();

  /// Ask for a move. [startFen] is the position the game started from.
  /// [uciMoves] is every move played since then (both sides), oldest first.
  /// The engine must NOT modify [uciMoves].
  /// Throwing, or returning a move the referee rejects, loses the game.
  Future<EngineMoveResult> getMove(String startFen, List<String> uciMoves, SearchLimits limits);

  /// Optional: perft from [fen] to [depth] using this version's own move generator.
  /// Lets one test validate every snapshot. Return null if not supported.
  int? perft(String fen, int depth) => null;
}
```

**Why start FEN + move list, not just the current FEN?** Repetition detection. A bare FEN has no
history, so the engine couldn't know a position had already occurred twice. Replaying the moves
rebuilds its `hashHistory` properly. It's also exactly what UCI does
(`position fen … moves …`), so a real UCI adapter later is trivial.

### 1.2 Creating the snapshot: `tool/snapshot_engine.dart`

You'll do this once per version, so script it. Usage:

```
dart run tool/snapshot_engine.dart --from lib/chess_engine --to v1     # first time only
dart run tool/snapshot_engine.dart --from v1 --to v2                   # from then on
```

Logic:

1. Resolve the source dir (`lib/chess_engine` or `lib/engines/<from>`) and the destination
   `lib/engines/<to>`. **Refuse** if the destination exists.
2. Recursively copy every `.dart` file.
3. For the first snapshot only, also copy `lib/extensions/` into `lib/engines/v1/extensions/`,
   because `fen_utility.dart` uses `string_extension.dart`.
4. In every copied file, rewrite imports with plain string replacement:
   - `package:ace/chess_engine/` → `package:ace/engines/<to>/`
   - `package:ace/extensions/` → `package:ace/engines/<to>/extensions/`
   - `package:ace/engines/<from>/` → `package:ace/engines/<to>/`
5. Print a summary: N files copied, M imports rewritten.

Use `dart:io` (`Directory.list(recursive: true)`, `File.readAsString`, `File.writeAsString`).
About 60 lines.

When copying v1→v2 the adapter comes along too. Only its `id`/`displayName` need changing.

### 1.3 `lib/engines/v1/adapter.dart`

This is the most important file in the phase. It wraps the frozen v1 code **without
editing it**.

```dart
import 'dart:async';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/v1/ai/engine.dart';
import 'package:ace/engines/v1/core/board.dart';
import 'package:ace/engines/v1/core/move.dart';
import 'package:ace/engines/v1/core/move_generator.dart';
import 'package:ace/engines/v1/core/zobrist.dart';

class AceEngine implements ChessEngine {
  @override String get id => 'v1';
  @override String get displayName => 'ACE v1';

  static bool _zobristReady = false;
  late Engine _engine;

  AceEngine() { _initZobrist(); _engine = Engine(); }

  static void _initZobrist() {
    if (_zobristReady) return;
    Zobrist();               // fills the static random tables for THIS snapshot's library
    _zobristReady = true;
  }

  @override
  Future<void> newGame() async { _engine = Engine(); }

  @override
  Future<EngineMoveResult> getMove(String startFen, List<String> uciMoves, SearchLimits limits) async {
    final board = Board.fromFEN(startFen);
    final gen = MoveGenerator();
    for (final uci in uciMoves) {
      final move = _findMove(gen.generateLegalMoves(board), uci);
      if (move == null) {
        throw StateError('v1 move generator does not think $uci is legal (after ${uciMoves.indexOf(uci)} plies)');
      }
      board.makeMove(move);
    }

    int? completedDepth;
    final depthPattern = RegExp(r'After searching with depth (\d+)');
    final best = await runZoned(
      () => _engine.getBestMove(board, limits.moveTime.inMilliseconds),
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
        final m = depthPattern.firstMatch(line);
        if (m != null) completedDepth = int.parse(m.group(1)!);
        // swallow everything else: v1 prints a lot
      }),
    );

    if (best == null || best.startingSquare < 0) {
      throw StateError('v1 returned no move');
    }
    final info = _engine.debugInfo;
    return EngineMoveResult(
      toUci(best),
      eval: _engine.bestEval,
      depth: completedDepth,
      nodes: info.numNodes + info.numQNodes,
    );
  }

  @override
  int? perft(String fen, int depth) { /* same as test/perft_test.dart performPerft, on Board.fromFEN(fen) */ }
}
```

Helpers in the same file (they're adapter code, so they don't count as editing v1):

- `String squareName(int index)`: v1 uses index 0 = a8, 7 = h8, 56 = a1, 63 = h1.
  `file = index % 8`, `rank = 8 - index ~/ 8`, giving `'abcdefgh'[file] + '$rank'`.
- `String toUci(Move m)` (private to this adapter, because it depends on v1's `Move` class): `squareName(m.startingSquare) + squareName(m.targetSquare)`, plus a
  promotion suffix from `m.promotion`: `1→'q'`, `2→'n'`, `3→'r'`, `4→'b'` (see
  `Move.promotingPiece()`). **Don't use `Move.toChessNotation()`. It drops the promotion piece
  (bug B1).** Castling is the king's move (`e1g1`), which is what v1 already generates.
- `Move? _findMove(List<Move> legal, String uci)`: return the first `m` where `toUci(m) == uci`.

#### ⚠️ Gotchas the adapter handles (read these)

1. **Zobrist must be initialised.** `Zobrist`'s tables are `static` and stay **all zeros** until
   something calls `Zobrist()`. Today `GameProvider` does that. In the CLI nothing would, so every
   position would hash to 0. The transposition table would return garbage and `hashHistory` would
   think every position was a threefold repetition. Each snapshot is a separate library with its own
   statics, so **each adapter initialises its own copy, once**. Don't call `Zobrist()` again later:
   it re-randomises the tables.
   _This only applies to versions that use Zobrist._ The match manager, the referee and the
   `ChessEngine` interface never use or require it. It's an internal detail of an engine. A version
   without Zobrist simply has no `Zobrist()` call in its adapter (see "Removing Zobrist from a
   version" in Phase 10).
2. **`print` spam.** `runZoned` with a `print` override swallows v1's output without touching v1's
   code. It also gives us search depth for free.
3. **Build a fresh `Board` every move.** It's cheap (replaying ≤ 600 moves) and means nothing leaks
   between moves or games.
4. **Two instances of the same version** (v1 vs v1) work fine: the shared static Zobrist tables are
   read-only after init, and everything else is per-instance.

### 1.4 Random engine: moved to Phase 2.7

It needs a legal move list, which the referee provides. Leave the `'random'` registry line commented
out until then.

### 1.5 `lib/engines/engine_registry.dart`

```dart
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/random/random_engine.dart';
import 'package:ace/engines/v1/adapter.dart' as v1;
// import 'package:ace/engines/v2/adapter.dart' as v2;

class EngineRegistry {
  /// Ordered oldest → newest. Add a line per new version.
  static final Map<String, ChessEngine Function()> _factories = {
    'v1': () => v1.AceEngine(),
    // 'v2': () => v2.AceEngine(),
  };
  static final Map<String, ChessEngine Function()> _testEngines = {
    // 'random': () => RandomEngine(),   // added in Phase 2.7
  };

  static List<String> get versionIds => _factories.keys.toList();                    // for the app picker
  static List<String> get allIds => [..._factories.keys, ..._testEngines.keys];      // for the CLI
  static String get latestId => _factories.keys.last;
  static ChessEngine create(String id) {
    final f = _factories[id] ?? _testEngines[id];
    if (f == null) throw ArgumentError('Unknown engine "$id". Known: ${allIds.join(', ')}');
    return f();     // ALWAYS a new instance, which is required for v1-vs-v1
  }
}
```

Prefixed imports (`as v1`) mean every adapter can use the same class name, `AceEngine`.

### 1.6 Tests (`test/engines/`)

- `adapter_test.dart` (run for every id in `EngineRegistry.versionIds`):
  - From the start position with `[]`, it returns a well-formed UCI move
    (`^[a-h][1-8][a-h][1-8][qrbn]?$`) that appears in v1's own legal move list. Use `moveTime: 50ms`.
    (In Phase 2.7 you'll strengthen this to "legal per the Referee".)
  - From `'4k3/1P6/8/8/8/8/8/4K3 w - - 0 1'` the returned move starts with `b7b8` and **has 5
    characters** (promotion suffix present).
  - Replaying `['e2e4','e7e5','g1f3','b8c6','f1c4','g8f6','e1g1']` (includes castling) doesn't
    throw.
  - An en passant line, e.g. `['e2e4','a7a6','e4e5','d7d5','e5d6']`, doesn't throw.
  - An unknown/illegal move in the history (`['e2e5']`) throws `StateError`.
  - Calling `getMove` twice on the same instance, and `newGame()` between, works.
- `perft_all_versions_test.dart`: move the 5 cases from `test/perft_test.dart` here and run them
  against `EngineRegistry.create(id).perft(...)` for every version. Cap depth so it runs in < 1 min.
- `snapshot_purity_test.dart`: for each `lib/engines/v*/` folder, read every `.dart` file and
  assert every `import` is `dart:…` or `package:ace/engines/<sameVersion>/…`. The only exception
  is `adapter.dart`, which may also import `package:ace/engines/engine_interface.dart`. This
  stops you from accidentally coupling v3 to v2's code.

**Done when:** `lib/engines/v1/` exists, it's byte-identical to `lib/chess_engine/` apart from import
paths (check with `diff -r`), and all the tests above pass. Leave `lib/chess_engine/` in place for
now because the app still uses it until Phase 9.

---

## Phase 2: The referee (your own rules code, no packages)

The referee is the neutral judge. It's used by the match manager now and by the app in Phase 9. It's
built from **your own code** in two parts:

1. **A rules core:** a separate, frozen copy of today's board / move generator / FEN code in
   `lib/referee/rules/`. It already passes perft, so it's a proven move generator.
2. **Three things you write fresh:** UCI move matching, game-end detection, and SAN (the `Nf3` /
   `exd5` notation that PGN files use).

> **The trade-off, honestly.** The rules core starts from the same code as v1. So any rules bug
> v1 has _today_, the referee has too, and it won't catch v1 making that mistake. It **will** catch
> every _new_ bug you introduce in v2, v3… (a bitboard rewrite, a faster move generator, a changed
> `makeMove`), which is the real risk from here on. Two habits keep it trustworthy:
>
> - The perft suite in 2.6 is stronger than today's. Perft is the best proof a move generator is
>   correct.
> - **Never edit `lib/referee/rules/` to make an engine pass.** Only fix genuine rules bugs, and add
>   a test with each fix.

### 2.1 Create the rules core

Copy `core/`, `helpers/` and `extensions/` (**not** `ai/`) from `lib/chess_engine/` into
`lib/referee/rules/`, rewriting imports to `package:ace/referee/rules/…`. The easiest way is to give
`tool/snapshot_engine.dart` a `--dest <path>` option and a `--no-ai` flag. Doing it by hand once is
also fine (it's about 10 files).

Then make these **referee-only fixes** inside `lib/referee/rules/`. They're allowed because the
referee isn't an engine being measured.

| #   | File                                             | Change                                                                                                                                                                                               | Why                                                                        |
| --- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| R1  | `helpers/fen_utility.dart` `loadPositionFromFEN` | Tolerate FENs with 4 fields (default half-move `0`, full-move `1`). Store the half-move clock under a correctly named field, `halfMoveClock`, instead of `plyCount`. Also parse the full-move number | Opening FENs vary. Today a 4-field FEN crashes on `sections[4]`            |
| R2  | `core/board.dart` `Board.fromFEN`                | `fiftyMoveRule = loadedPositionInfo.halfMoveClock;`                                                                                                                                                  | Otherwise the fifty-move rule is wrong for positions that don't start at 0 |
| R3  | `helpers/board_helper.dart`                      | Add `squareName(int)` and `squareIndex(String)` (see 2.3)                                                                                                                                            | Index ⇄ `"e4"` conversion for UCI, used by the referee and the app         |

Don't touch `makeMove`/`unMakeMove`/the move generator.

The `snapshot_purity_test.dart` from Phase 1 should also cover `lib/referee/rules/`: it may only
import `dart:*` and itself.

### 2.2 `lib/referee/game_end.dart`

```dart
enum GameOutcome { whiteWins, blackWins, draw }

enum GameTermination {
  checkmate, stalemate, threefoldRepetition, fiftyMoveRule, insufficientMaterial,
  maxMoves,        // our 300-move cap
  illegalMove,     // engine returned a move the referee rejected (or malformed text)
  engineError,     // engine threw / returned no move
}

class GameEnd {
  final GameOutcome outcome;
  final GameTermination termination;
  final String? detail;        // human-readable, for logs and PGN comment
  const GameEnd(this.outcome, this.termination, [this.detail]);
  String get pgnResult => switch (outcome) { GameOutcome.whiteWins => '1-0', GameOutcome.blackWins => '0-1', GameOutcome.draw => '1/2-1/2' };
}
```

### 2.3 Square-name helpers: in the referee's `BoardHelper`

There's no separate utils file. Add two static methods to the referee's copy of
`lib/referee/rules/helpers/board_helper.dart` (next to `getFileFromIndex`/`getRankFromIndex`):

- `static String squareName(int index)`: a8 = 0 … h1 = 63, so `'abcdefgh'[getFileFromIndex(index)] + '${8 - getRankFromIndex(index)}'`.
- `static int squareIndex(String name)`: the inverse, `(8 - rank) * 8 + file`.

These are additions, not rules changes, so they're fine in the frozen rules copy (see R3 in 2.1).
The referee and the app (Phase 9) use `BoardHelper.squareName`/`squareIndex`. The v1 adapter keeps its
own private copy, because snapshots can't import outside themselves.

> **Where's `toUci`?** Converting a `Move` to UCI depends on how that `Move` is represented, and
> that's private to each codebase. So there's **no shared `toUci`**. Each side owns its own:
>
> - **Each engine's adapter** has a private `toUci`/`_findMove` for _its_ `Move` type (Phase 1.3).
>   A future v5 with bitboards and 16-bit packed moves writes a different one in its own adapter.
> - **The referee** has a private `_toUci` in `referee.dart` for the _referee's_ `Move`
>   (`lib/referee/rules/core/move.dart`).
>
> UCI strings are the only thing they share. That's the whole point of the string interface.

### 2.4 `lib/referee/san.dart`: writing and reading SAN

SAN is needed in two places: **reading** your openings PGN and **writing** `games.pgn`. The trick that
keeps this small is that **reading uses writing.** To parse `"Nbd2"`, generate the SAN for every legal
move and pick the one that matches.

```dart
class San {
  /// SAN for [move], which must be legal in [board]'s current position. [legal] = all legal moves here.
  /// Set [withCheck] to false to skip the +/# suffix (faster; used when parsing).
  static String fromMove(Board board, Move move, List<Move> legal, {bool withCheck = true});

  /// The legal move matching a SAN token, or null if none matches (illegal or ambiguous).
  static Move? parse(Board board, String token, List<Move> legal);
}
```

**`fromMove` rules**, in order:

1. **Castling:** if `move.castling`, return `'O-O'` when the target file is g (`targetSquare % 8 == 6`),
   else `'O-O-O'`. Then add the check suffix (step 6).
2. `type = Piece.type(board.position[move.startingSquare])`. The letters are K, Q, R, B, N.
   A pawn gets no letter.
3. `isCapture = board.position[move.targetSquare] != Piece.none || move.enPassantCapture`.
4. **Pawn moves:** if it's a capture, the start file letter + `'x'`. Then the target square. If it's a
   promotion, add `'='` + `'QNRB'[move.promotion - 1]` (v1 codes: 1 = Q, 2 = N, 3 = R, 4 = B).
   Examples: `e4`, `exd5`, `exd6` (en passant), `b8=Q`, `bxa8=N`.
5. **Piece moves:** letter + disambiguation + (`'x'` if capture) + target square.
   **Disambiguation:** `others` = the legal moves with the same piece type, the same target, and a
   different start square.
   - `others` is empty, so add nothing (`Nf3`).
   - No other shares the start **file**, so add the file (`Nbd2`).
   - Otherwise, if no other shares the start **rank**, add the rank (`R1a3`).
   - Otherwise add both (`Qa3b2`).
6. **Check suffix** (only if `withCheck`): `board.makeMove(move)`, then generate the replies with a
   **separate** `MoveGenerator` instance, read its `inCheck`, and `board.unMakeMove(move)`. If in
   check, add `'#'` when there are no replies, else `'+'`.
   > Use a separate generator because `generateLegalMoves` overwrites the generator's internal state
   > (`inCheck`, attack maps). If the referee's main generator were reused here, its `inCheck` would
   > describe the wrong position.

**`parse` rules:**

1. Normalise the token: strip trailing `+ # ! ?` characters. `0-0-0` becomes `O-O-O` and `0-0` becomes
   `O-O`. Accept a promotion written without `=` (`e8Q` becomes `e8=Q`).
2. For each legal `m`: if `fromMove(board, m, legal, withCheck: false) == normalised`, return `m`.
3. Return null. That covers illegal moves **and** ambiguous ones like plain `Nd2` when two knights
   can reach d2, which is correct because that's invalid SAN.

### 2.5 `lib/referee/referee.dart`

```dart
class Referee {
  Referee(String startFen, {this.maxPlies = 600});
  final String startFen;
  final int maxPlies;                         // plies played after startFen

  String get fen;                             // full 6-field FEN of the current position
  bool get whiteToMove;
  int pieceAt(int index);                     // the int piece code, used by the app's board UI
  List<String> get uciHistory;                // unmodifiable view
  List<String> get sanHistory;                // for PGN
  int get pliesPlayed;
  List<String> legalUciMoves();               // used by RandomEngine & the app

  /// Returns null if legal and applied, otherwise a reason ("malformed: …", "illegal: e2e5").
  String? tryPlayUci(String uci);

  /// Same, but for a SAN token. Used by the opening loader.
  String? tryPlaySan(String san);

  /// Returns null while the game is still on.
  GameEnd? checkGameEnd();
}
```

Implementation notes:

- **Fields:** `Board _board`, `MoveGenerator _gen`, `List<Move>? _legalCache`, `int _fullMoveNumber`,
  `Map<String,int> _repetitions`, `List<String> _uci, _san`.
- **Zobrist:** `Board` updates a Zobrist key on every move, so initialise the referee copy's tables
  once (`static bool _zobristReady`), exactly like the adapter does. The referee doesn't _use_ the
  hash. Repetition uses FEN keys (below), so the referee doesn't depend on hashing being right.
- **Constructor:** `_board = Board.fromFEN(startFen)`. Read `_fullMoveNumber` from FEN field 6
  (default 1). Record the starting position in `_repetitions`.
- **`_legal()`:** `_legalCache ??= _gen.generateLegalMoves(_board)`. Set `_legalCache = null` after
  every move. Read `_gen.inCheck` **right after** generating for the current position.
- **`fen`:** `FENUtility.fenFromBoard(_board)` gives 4 fields. Append `' ${_board.fiftyMoveRule} $_fullMoveNumber'`.
- **`tryPlayUci`:**
  1. Validate the format: `RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')`. If it doesn't match, it's malformed.
  2. Find the move: the first `m` in `_legal()` where `_toUci(m) == uci`. `_toUci` is a private method
     on `Referee`: `BoardHelper.squareName(m.startingSquare) + BoardHelper.squareName(m.targetSquare)`, plus `'qnrb'[m.promotion - 1]`
     if `m.promotion != 0`. If there isn't one, it's illegal.
     That makes `e7e8` (no piece) **illegal** when a promotion is required. That's correct and strict.
  3. Call `_apply(m)`.
- **`tryPlaySan`:** `m = San.parse(_board, san, _legal())`. If it's null, return `'illegal or ambiguous SAN: $san'`.
  Otherwise call `_apply(m)`.
- **`_apply(m)`:** `san = San.fromMove(_board, m, _legal())` **before** making the move. Then
  `wasBlack = !_board.whiteToPlay`, `_board.makeMove(m)`, and if `wasBlack` do `_fullMoveNumber++`.
  Push the UCI and SAN, clear `_legalCache`, and increment `_repetitions[key]`.
- **Repetition key:** the first 4 FEN fields (pieces, side, castling, en passant). This avoids
  relying on Zobrist. Threefold = the current key's count ≥ 3.
- **Insufficient material:** move the logic from `GameProvider._getGameResult` into a private method
  `_insufficientMaterial()`: K v K, K+B v K, K+N v K, and K+B v K+B with bishops on the same colour
  square. (In the existing code, `whiteBishopRank`/`File` are swapped in name only. The parity
  `(file + rank) % 2` is still correct.)
- **`checkGameEnd()` order** (the order matters):
  1. `legal = _legal()`. If it's empty: when `_gen.inCheck`, it's **checkmate** and the side that
     just moved wins. Otherwise it's **stalemate**.
  2. Insufficient material is a draw.
  3. Repetition count ≥ 3 is a draw.
  4. `_board.fiftyMoveRule >= 100` is a draw.
  5. `pliesPlayed >= maxPlies` is a draw (`maxMoves`).
  6. Otherwise `null`.
     Mate is checked first because mate on the 100th half-move counts as mate.

### 2.6 Tests

**`test/referee/san_test.dart`**
| Position (FEN) | Move | Expected SAN |
|---|---|---|
| start | g1f3, e2e4 | `Nf3`, `e4` |
| `4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1` | b1d2 / f3d2 | `Nbd2` / `Nfd2` (file disambiguation) |
| `4k3/8/8/R7/8/8/8/R3K3 w - - 0 1` | a1a3 / a5a3 | `R1a3` / `R5a3` (rank disambiguation) |
| `4k3/8/8/8/8/Q1Q5/8/Q3K3 w - - 0 1` | a1b2 / a3b2 / c3b2 | `Q1b2` / `Qa3b2` / `Qcb2` |
| after `e2e4 d7d5` | e4d5 | `exd5` |
| after `e2e4 a7a6 e4e5 d7d5` | e5d6 | `exd6` (en passant) |
| `r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1` | b7b8q / b7a8n | `b8=Q+` / `bxa8=N` |
| after `e2e4 e7e5 g1f3 b8c6 f1c4 g8f6` | e1g1 | `O-O` |
| after `f2f3 e7e5 g2g4` | d8h4 | `Qh4#` |

Also:

- `parse` accepts `Nf3+`, `0-0`, `e8Q`, `exd5!?`. It returns null for `Nf4` at the start and for a plain
  `Nd2` in the two-knights position (ambiguous).
- **Round trip (the most valuable test):** play 20 random games of up to 200 plies with a seeded
  `Random`. At every ply, for every legal move `m`, check `San.parse(board, San.fromMove(board, m, legal), legal)` returns `m`.

**`test/referee/referee_test.dart`**
| Test | Setup | Expect |
|---|---|---|
| legal move | start, `e2e4` | null, `uciHistory == ['e2e4']`, `sanHistory == ['e4']` |
| illegal | start, `e2e5` | non-null reason, history unchanged |
| malformed | `'E2E4'`, `'e2'`, `'e7e8k'` | non-null |
| promotion strict | `'4k3/1P6/8/8/8/8/8/4K3 w - - 0 1'`, `b7b8` | rejected; `b7b8q` accepted and SAN contains `=Q` |
| underpromotion | same, `b7b8n` | accepted |
| castling | after `e2e4 e7e5 g1f3 b8c6 f1c4 g8f6`, `e1g1` | accepted, SAN `O-O` |
| en passant | `e2e4 a7a6 e4e5 d7d5 e5d6` | accepted |
| SAN play | start, `tryPlaySan('Nf3')` | null, `uciHistory == ['g1f3']` |
| fool's mate | `f2f3 e7e5 g2g4 d8h4` | `blackWins`, `checkmate` |
| stalemate | `'7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'` | `draw`, `stalemate` |
| threefold | start, `g1f3 g8f6 f3g1 f6g8` ×2 | `draw`, `threefoldRepetition` after the 8th ply, not before |
| fifty-move | `'8/8/8/8/8/8/R7/K6k w - - 99 80'` + `a2b2` | `fiftyMoveRule` |
| insufficient | `'8/8/8/8/8/8/8/K6k w - - 0 1'` | `insufficientMaterial` |
| max plies | `Referee(start, maxPlies: 4)` + `g1f3 g8f6 f3g1 f6g8` | `maxMoves` |
| 4-field FEN | `'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -'` | constructs fine, `fen` ends `0 1` |
| fen output | start, `e2e4` | `fen` ends with `b KQkq e3 0 1` (check the en passant field matches what v1 produces), then after `e7e5 g1f3` the clocks are `1 2` |

**`test/referee/rules_perft_test.dart`**: perft on the referee's own board, using **all** the depths in
today's `perft_test.dart` plus these two well-known extra positions:
| FEN | Depth 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| `r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10` | 46 | 2,079 | 89,890 | 3,894,594 |
| `n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1` (promotions) | 24 | 496 | 9,483 | 182,838 |

If any of these fail, you've found a real rules bug that v1 has too. Fix it in the referee, and note
it in §11 as a v1 bug for v2.

**Done when:** all referee, SAN and perft tests pass.

### 2.7 `lib/engines/random/random_engine.dart`

Now that the referee exists: a `ChessEngine` with `id 'random'` that builds `Referee(startFen)`,
replays `uciMoves` with `tryPlayUci`, and returns a random entry from `legalUciMoves()`. Take an
optional `int? seed` for `Random(seed)`. Add it to the registry's `_testEngines`. It's used for sanity
matches (v1 should crush it) and in tests. Also go back to `adapter_test.dart` and add the
assertion that v1's move is in `Referee(start).legalUciMoves()`.

---

## Phase 3: Loading your openings

### 3.0 Look at your PGN first

Open `match_data/openings.pgn` and work out which of these shapes it is. The loader handles all of them:

- **(a)** Many short games, each just an opening line (e.g. 8 plies). Use the **final position**.
- **(b)** Full games. Use the position after the first **N plies** (`--opening-plies N`).
- **(c)** Games with a `[FEN "…"]` header. Start from that FEN, then apply the moves.
- Count the games. You need ≥ 500 positions for 1000 games without reuse. If there are fewer, the loader
  cycles through them and prints a warning.

### 3.1 `lib/match_manager/opening_book.dart`

```dart
class OpeningPosition {
  final int index;           // 0-based position in the file
  final String fen;
  final String? name;        // from [Opening "…"] / [ECO "…"] / [Event "…"] if present
  const OpeningPosition(this.index, this.fen, this.name);
}

class OpeningBook {
  final List<OpeningPosition> positions;
  final List<String> warnings;           // skipped/invalid games, duplicates
  OpeningBook._(this.positions, this.warnings);

  static OpeningBook fromPgnFile(String path, {int? openingPlies});
  static OpeningBook fromPgnString(String pgn, {int? openingPlies});   // used by tests
}
```

### 3.1b `lib/match_manager/pgn_reader.dart`: your own PGN tokeniser

```dart
class PgnGame {
  final Map<String, String> headers;   // e.g. {'Event': '…', 'FEN': '…'}
  final List<String> sanMoves;         // just the move tokens, in order
  final String? result;                // '1-0', '0-1', '1/2-1/2', '*' or null
  const PgnGame(this.headers, this.sanMoves, this.result);
}

class PgnReader {
  static List<PgnGame> parseMany(String text);
}
```

Algorithm (a small state machine, ~80 lines):

1. Normalise line endings (`\r\n` → `\n`). Process line by line.
2. **Header line:** the trimmed line starts with `[` and ends with `]`. Match it with
   `RegExp(r'^\[(\w+)\s+"(.*)"\]$')`. If the current game already has moves, **finish it first**
   (this is how games are split). Then store the tag.
3. **Movetext lines:** scan character by character so you can skip:
   - `{ … }` comments, which can span lines, so keep an "in comment" flag across lines,
   - `;` to the end of the line,
   - `( … )` variations, which **can nest**, so keep a depth counter and only collect tokens at depth 0,
   - `$12`-style NAGs.
     Everything else gets split on whitespace into tokens.
4. **Each token:**
   - Strip a leading move number with `RegExp(r'^\d+\.+')` (handles `1.`, `1...`, `12.`, and `1.e4` written
     without a space). Skip it if what's left is empty.
   - `1-0`, `0-1`, `1/2-1/2` or `*` is the result. **Finish the game.** This is how header-less files are
     split.
   - Anything else is a SAN move, so add it to `sanMoves`.
5. At the end of the file, finish any game that has moves.

### 3.1c Turning games into positions (`OpeningBook.fromPgnString`)

1. `games = PgnReader.parseMany(pgn)`.
2. For each game `g` (index `i`):
   - `referee = Referee(g.headers['FEN'] ?? startPositionFen)`.
   - Play `g.sanMoves` in order with `referee.tryPlaySan(token)`. If `openingPlies != null`, stop after that many.
     If a move fails, add a warning (`'Game ${i+1}, ply ${n+1}: "$token" (reason)'`) and **skip the game**.
   - If the game is shorter than `openingPlies`, warn and use its final position.
   - If `referee.checkGameEnd() != null`, warn and skip it. You can't start from a finished game.
   - `fen = referee.fen`. **Dedupe** on the first 4 FEN fields and warn about duplicates.
   - The name comes from the `Opening`/`ECO`/`Event` headers (optional, for nicer PGN `Event` tags).

### 3.2 Tests

**`test/match_manager/pgn_reader_test.dart`**:

- Two headed games become 2 `PgnGame`s with the correct headers and moves.
- Header-less `1. e4 e5 2. Nf3 * 1. d4 d5 *` becomes 2 games.
- `1. e4 {best by test} e5 (1... c5 2. Nf3 (2. c3)) 2. Nf3 $1 ; comment` gives `['e4','e5','Nf3']`.
  This covers comments, nested variations, NAGs and line comments.
- `1.e4 e5 2.Nf3 Nc6` (no spaces after the dots) and `3... Nf6` black move numbers parse correctly.
- A multi-line `{ … }` comment is skipped.

**`test/match_manager/opening_book_test.dart`**, with fixture `test/fixtures/openings_sample.pgn` containing 4
games: a headed 8-ply line, a headless line `1. d4 d5 2. c4 e6 *`, a game with a `[FEN]` header, and
a deliberately broken one (`1. e4 e4`).

- Loads 3 positions with 1 warning.
- The first FEN equals what you get by playing the same moves as UCI into a `Referee` by hand.
- `openingPlies: 2` on the headed game gives the FEN after its first two plies.
- A duplicate game produces a duplicate warning and isn't added twice.
- Load your real `match_data/openings.pgn` and print the count and warnings (a "smoke test", not a strict assertion).
  **Every warning here is either a quirk of your file or a bug in your PGN reader / SAN parser.
  Investigate each one.**

**Done when:** your real file loads with a sensible count and you understand every warning.

---

## Phase 4: Playing one game

### 4.1 `lib/match_manager/game_record.dart`

```dart
class MoveStat {
  final int timeMs; final int? depth; final int? nodes; final int? eval;
  const MoveStat(this.timeMs, this.depth, this.nodes, this.eval);
}

class GameRecord {
  final int gameNumber;           // 1-based
  final int openingIndex;
  final String startFen;
  final String whiteId, blackId;  // engine ids
  final String whiteName, blackName;
  final GameEnd end;
  final List<String> uciMoves, sanMoves;
  final List<MoveStat> moveStats; // one per ply, same order as moves
  final String? errorDetail;      // stack trace / referee reason for illegalMove & engineError
  final DateTime startedAt; final Duration duration;
  // constructor…
}
```

### 4.2 `lib/match_manager/game_runner.dart`

```dart
class GameRunner {
  Future<GameRecord> playGame({
    required int gameNumber,
    required OpeningPosition opening,
    required ChessEngine white,
    required ChessEngine black,
    required SearchLimits limits,
    required int maxPlies,
  }) async { … }
}
```

The loop:

```
referee = Referee(opening.fen, maxPlies: maxPlies)
await white.newGame(); await black.newGame()
loop:
  end = referee.checkGameEnd();  if end != null → return record(end)
  mover = referee.whiteToMove ? white : black
  moverLoses = referee.whiteToMove ? GameOutcome.blackWins : GameOutcome.whiteWins
  sw = Stopwatch()..start()
  try:
    result = await mover.getMove(opening.fen, List.unmodifiable(referee.uciHistory), limits)
  catch (e, st):
    return record(GameEnd(moverLoses, engineError, '${mover.id}: $e'), errorDetail: '$e\n$st')
  sw.stop()
  reason = referee.tryPlayUci(result.uciMove.trim().toLowerCase())
  if reason != null:
    return record(GameEnd(moverLoses, illegalMove, '${mover.id} played "${result.uciMove}" ($reason) in ${referee.fen}'))
  moveStats.add(MoveStat(sw.elapsedMilliseconds, result.depth, result.nodes, result.eval))
```

Notes:

- **Pass the history list as unmodifiable** so a buggy engine can't corrupt the referee.
- **Time overruns are logged, not punished.** You can't stop a running Dart function from inside
  the same isolate (see §12). Record `timeMs` and report the max/average overrun in the summary.
- **What can't be caught:** a true infinite loop hangs the match. Ctrl-C, find the culprit in the
  error log / last game, and fix it. (Isolates would solve this, see §12.)

### 4.3 Test doubles: `test/helpers/fake_engines.dart`

- `ScriptedEngine(List<String> moves)` returns the next scripted move each call.
- `IllegalEngine` always returns `'e2e5'`.
- `CrashingEngine` throws `Exception('boom')`.
- `MalformedEngine` returns `'xyz'`.
- `NoMoveEngine` returns `''`.
- `CountingEngine` wraps another engine and counts `newGame()`/`getMove()` calls.

### 4.4 Tests (`test/match_manager/game_runner_test.dart`)

- Scripted fool's mate (White: `f2f3, g2g4`; Black: `e7e5, d8h4`) gives `blackWins`/`checkmate`,
  4 SANs.
- `IllegalEngine` as White gives `blackWins`/`illegalMove`, and `detail` contains `e2e5`.
- `CrashingEngine` as Black (with a scripted White) gives `whiteWins`/`engineError`, and `errorDetail`
  contains `boom`.
- `MalformedEngine` and `NoMoveEngine` give `illegalMove`.
- `RandomEngine` vs `RandomEngine` with `maxPlies: 20` ends with **some** termination within 20 plies
  and never throws.
- `newGame()` is called once per engine per game.
- A real `v1` vs `RandomEngine`, 1 game, `moveTime: 20ms`, `maxPlies: 60`, completes. (Mark this
  test as slow if you like.)

**Done when:** all tests pass and v1 can play a whole game against Random.

---

## Phase 5: Running a match and computing stats

### 5.1 `lib/match_manager/match_config.dart`

```dart
class MatchConfig {
  final String engineAId, engineBId;
  final int games;                 // default 1000, must be even
  final Duration moveTime;         // --movetime, default 100ms
  final int maxMoves;              // default 300 (→ maxPlies = 600)
  final String openingsPath;       // default match_data/openings.pgn
  final int? openingPlies;
  final int? openingSeed;          // null = file order; else shuffle with Random(seed)
  final String outDir;             // default match_results
  int get maxPlies => maxMoves * 2;
}
```

### 5.2 The schedule (`lib/match_manager/match_runner.dart`)

```
pairs = games ~/ 2
positions = book.positions (optionally shuffled with openingSeed)
if positions.length < pairs: warn "only X positions, cycling"
for p in 0 ..< pairs:
  opening = positions[p % positions.length]
  game 2p+1: A = white, B = black
  game 2p+2: B = white, A = black
```

Swapping colours on the **same** position cancels out unbalanced openings. Interleaving the two games
(rather than "all A-white games first") means a match stopped half-way is still fair.

```dart
class MatchRunner {
  MatchRunner(this.config, {this.onGameFinished});
  final void Function(GameRecord record, MatchStats statsSoFar)? onGameFinished;
  Future<MatchStats> run({required OpeningBook book, required ChessEngine engineA, required ChessEngine engineB});
}
```

Create **one instance per engine** for the whole match and call `newGame()` per game. The CLI
creates the instances via `EngineRegistry.create` (two separate instances even for v1 vs v1).

### 5.3 `lib/match_manager/elo.dart` (pure functions, easy to test)

Scores are from engine **A**'s point of view. `N = W + D + L`.

```
score  μ = (W + 0.5·D) / N
elo(μ)   = -400 · log10(1/μ − 1)               // +∞ if μ = 1, −∞ if μ = 0
per-game variance  σ² = (W/N)(1−μ)² + (D/N)(0.5−μ)² + (L/N)(0−μ)²
standard error     se = sqrt(σ² / N)
95% bounds         μ± = μ ± 1.959964·se
elo error (±)      = (elo(μ+) − elo(μ−)) / 2
LOS (likelihood of superiority) = 0.5 · (1 + erf((W − L) / sqrt(2·(W + L))))
```

Dart's `dart:math` has no `erf`. Implement the Abramowitz–Stegun approximation (7.1.26). It's 6
lines and accurate to ~1e-7, which is plenty. Clamp μ to `[1e-6, 1−1e-6]` before `elo()` so a
10–0 sweep doesn't print `Infinity`, or special-case it and print `>+999`.

**Test values** (computed independently, use `closeTo(x, 0.05)`):
| W | D | L | μ | Elo | ± | LOS |
|---|---|---|---|---|---|---|
| 400 | 200 | 400 | 0.5000 | 0.00 | 19.28 | 0.5000 |
| 450 | 200 | 350 | 0.5500 | 34.86 | 19.35 | 0.9998 |
| 600 | 300 | 100 | 0.7500 | 190.85 | 19.30 | 1.0000 |

A useful rule of thumb to keep in mind: with 1000 games the error bar is about ±20 Elo, so a
change worth +10 Elo **can't be distinguished from noise in one 1000-game run**. That's what SPRT
(§12) solves.

### 5.4 `lib/match_manager/match_stats.dart`

```dart
class WdL { int w = 0, d = 0, l = 0; int get n => w + d + l; double get score => n == 0 ? 0 : (w + 0.5 * d) / n; }

class EngineSearchStats {           // one per engine
  int moves = 0; int totalTimeMs = 0; int maxTimeMs = 0;
  int depthSum = 0, depthCount = 0; int nodesSum = 0, nodesCount = 0;
  int overruns = 0;                 // moves where timeMs > moveTime + 50ms
  int illegalMoves = 0, crashes = 0;
  double get avgDepth …; double get avgNodes …; double get avgTimeMs …;
}

class MatchStats {
  MatchStats(this.engineAId, this.engineBId, this.moveTime);
  final WdL total = WdL(), aAsWhite = WdL(), aAsBlack = WdL();     // from A's view
  final Map<GameTermination, int> terminations = {};
  final Map<String, EngineSearchStats> search = {};                // keyed by engine id… see note
  int gamesPlayed = 0;
  void add(GameRecord r);
  EloResult get elo;                                               // uses elo.dart on `total`
  String toSummaryText();  Map<String, dynamic> toJson();
}
```

**v1 vs v1 note:** both engines share the id `v1`, so key the search stats by **role** (`'A'`/`'B'`)
and not by id. Work out the role per ply from who was White in that game.

In `add(r)`:

- `aIsWhite = (gameNumber is odd)`, or store it on the record. Storing it explicitly (`record.engineAIsWhite`) is cleaner.
- Translate `r.end.outcome` into A's W/D/L and add it to `total` plus `aAsWhite`/`aAsBlack`.
- `terminations[r.end.termination]++`.
- Walk `r.moveStats`. Ply `i` was played by White if `i` is even **and** the start FEN has White to move
  (if the opening FEN is Black to move, flip it). Add each stat to the right role.
- On `illegalMove`/`engineError`, increment the loser's role counter.

### 5.5 Tests

- `elo_test.dart`: the table above. Also `elo(0.5) == 0` and `LOS` with `W == L` is 0.5.
- `match_stats_test.dart`: feed hand-built `GameRecord`s (no engines needed) and check the W/D/L
  totals, colour split, termination counts, and role attribution when the start FEN is Black to move.
- `match_runner_test.dart`: with `ScriptedEngine`s/`RandomEngine`s and a 3-position book,
  `games: 6` plays positions `0,0,1,1,2,2` with colours alternating A,B,A,B,A,B. With
  `games: 8`, it cycles and warns. An odd `games` throws `ArgumentError`.

**Done when:** a `RandomEngine`(seed 1) vs `RandomEngine`(seed 2) 20-game match runs in a test and
produces a sensible `MatchStats`.

---

## Phase 6: Output files

### 6.1 `lib/match_manager/pgn_writer.dart`

```dart
class PgnWriter {
  static String gameToPgn(GameRecord r, {required String event, required Duration moveTime});
}
```

Format:

```
[Event "v1 vs v2"]
[Site "ACE match manager"]
[Date "2026.10.01"]
[Round "37"]
[White "ACE v2"]
[Black "ACE v1"]
[Result "1-0"]
[SetUp "1"]
[FEN "rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"]
[Termination "checkmate"]
[PlyCount "57"]
[TimeControl "movetime=100ms"]
[Opening "#12"]

3. Nxe5 {+0.31/7 98ms} d6 {-0.25/7 101ms} 4. Nf3 ... 1-0
```

Details that are easy to get wrong:

- **Move numbering starts from the FEN's full-move number** (field 6), not 1.
- If the start position is **Black to move**, the first token is `N... move` (e.g. `5... Nf6`).
- Per-move comments are optional but great when debugging: `{eval/depth time}`, with the eval in
  pawns (`eval/100`, 2 dp, explicit `+`). Leave out the parts that are null.
- For `illegalMove`/`engineError`, add a final comment before the result: `{v2 played "e2e5" (illegal) — forfeit}`.
- Wrap lines at ~80 characters. Separate games with a blank line. Use `\n` line endings.
- **Validate the output:** in a test, feed `gameToPgn(...)` back through your own `PgnReader.parseMany`
  plus `Referee.tryPlaySan` (or just `OpeningBook.fromPgnString`) and check you reach the same final FEN.
  Also paste a real game into Lichess's "Import game" once, as an outside check that your SAN is standard.

### 6.2 `lib/match_manager/match_output.dart`

Creates `match_results/<yyyy-MM-dd_HHmm>_<A>-vs-<B>/` containing:

| File           | Written                                                                      | Content                                                                                                                                                                      |
| -------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `config.txt`   | at the start                                                                 | all `MatchConfig` values, opening file path + count, and the git commit (`git rev-parse --short HEAD` via `Process.runSync`, wrapped in try/catch)                           |
| `games.pgn`    | **appended after every game** (so a crash or Ctrl-C keeps everything so far) | PGN                                                                                                                                                                          |
| `errors.log`   | appended on each `illegalMove`/`engineError`                                 | game number, engines, start FEN, UCI move list, the FEN at the failure, the detail/stack trace, and a `position fen … moves …` line you can paste straight into a debug test |
| `summary.txt`  | rewritten every 50 games and at the end                                      | the human summary (below)                                                                                                                                                    |
| `summary.json` | at the end                                                                   | `MatchStats.toJson()` for future tooling and graphs                                                                                                                          |

### 6.3 Summary format (`MatchStats.toSummaryText()`)

```
ACE v2 (A) vs ACE v1 (B) — 1000 games, 100 ms/move, openings: match_data/openings.pgn (512 positions)

Result (A's view):   +412 =301 -287    score 56.3%
Elo difference:      +43.7 ± 18.6  (95%)     LOS: 100.0%

                 W     D     L    score
A as White     231   148   121    61.0%
A as Black     181   153   166    51.5%

Terminations: checkmate 598, threefold 211, fifty-move 41, insufficient 37, stalemate 6, max-moves 6, illegal 1, crash 0

Search          avg depth   avg nodes   avg ms   max ms   overruns   illegal   crashes
A ACE v2           6.8      41,230      100.4    163         12         1         0
B ACE v1           6.1      38,900      101.9    410         88         0         0

Total time: 3h 12m
```

**Done when:** a 20-game Random-vs-Random match writes all 5 files, and `games.pgn` imports into Lichess.

---

## Phase 7: The CLI (`bin/match.dart`)

```
dart run bin/match.dart --a v2 --b v1 [--games 1000] [--movetime 100] [--max-moves 300]
                        [--openings match_data/openings.pgn] [--opening-plies N] [--seed N]
                        [--out match_results] [--quiet]
dart run bin/match.dart --list            # prints EngineRegistry.allIds
```

Use `package:args` `ArgParser`. Flow:

1. Parse the args. On `--help` or an error, print `parser.usage` and `exit(64)`.
2. Validate: both ids exist (`EngineRegistry.allIds`), `games` is even and > 0, `movetime` > 0.
3. Load the `OpeningBook` and print the count and each warning.
4. `MatchOutput.create(config)` and write `config.txt`.
5. Create the engines. Run `MatchRunner` with `onGameFinished` → write the PGN/errors and print progress:
   ```
   [ 37/1000] v2-v1 1-0 checkmate (61 ply, 14.2s) | A +15 =12 -10 | Elo +17 ± 98 | ETA 3h02m
   ```
   ETA = average game duration × games left. Unless `--quiet`, also print errors as they happen.
6. At the end, print the summary, write `summary.txt`/`summary.json`, and exit 0.
7. **Ctrl-C:** listen to `ProcessSignal.sigint.watch()`. On the first press set a `stopRequested` flag.
   `MatchRunner` checks it between games, finishes the current game, writes the summary, and exits.
   On a second press, exit immediately. Because the PGN is appended per game, you lose nothing.

**Speed tips:**

- Compile ahead of time for long runs: `dart compile exe bin/match.dart -o build/match` then
  `./build/match --a v2 --b v1`. AOT also starts faster and its timing is steadier than the JIT's warm-up.
- Expected duration: about 1000 games × ~120 plies × movetime. At **100 ms** that's ~3.3 h.
  At **50 ms**, ~1.7 h. At **20 ms**, ~40 min. For quick "did I break anything?" runs use
  `--games 100 --movetime 20`. Save the full 1000 × 100 ms for a version you believe in.
- Plug in your laptop and stop it sleeping (`caffeinate -i` on macOS).

**Done when:** `dart run bin/match.dart --a v1 --b random --games 20 --movetime 20` completes and
writes a results folder.

---

## Phase 8: Sanity-check the harness (very important)

Before trusting any v2 result, prove the harness itself is fair.

| Run                                          | Expect                                                                                                               | If not…                                                                                                                             |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `--a v1 --b random --games 50 --movetime 20` | v1 scores ~100%                                                                                                      | the adapter or referee is broken (look at `errors.log`)                                                                             |
| `--a v1 --b v1 --games 200 --movetime 50`    | Elo within **±(error bar)** of 0, roughly equal White/Black split between A and B, **zero** illegal moves or crashes | colour assignment or stats attribution is wrong. Or v1 has a rules bug, which is a real finding!                                    |
| Any run with `illegalMove` in v1             | investigate                                                                                                          | either the referee is wrong (write a referee test) or v1's movegen is wrong (write a perft test). This is the harness doing its job |

Also replay 2–3 PGNs from `games.pgn` in Lichess to make sure the moves look like the engine's play.

**Done when:** v1 vs v1 comes out at ~0 Elo, with zero errors.

---

## Phase 9: Picking an engine version in the app

Goal: the app uses the **referee** for rules and **`ChessEngine`** for the AI. A dropdown picks the version.

### 9.1 `GameProvider` rewrite (`lib/providers/game_provider.dart`)

State:

```dart
Referee _referee = Referee(startFen);
String _engineId = EngineRegistry.latestId;
ChessEngine _engine = EngineRegistry.create(EngineRegistry.latestId);
GameEnd? _gameEnd;              // replaces the Result enum + _getGameResult()
int? _selectedIndex;
bool _engineThinking = false;
int _thinkingTime = 2000;
```

Methods (keep the public names the GUI already uses where you can):

- `reset()` creates a new `Referee`, calls `_engine.newGame()`, and clears the selection.
- `List<String> get engineIds => EngineRegistry.versionIds;` and `String get engineId`.
- `Future<void> setEngine(String id)` creates `EngineRegistry.create(id)`, calls `reset()`, and calls `notifyListeners()`.
- `int pieceAt(int index) => _referee.pieceAt(index);` The referee's rules core uses the same int piece
  codes as today, so `PieceImage.forPiece` and `square.dart` keep working. Just switch `PieceImage`'s import
  of `Piece` to `package:ace/referee/rules/core/piece.dart`.
- `List<int> legalTargetsFrom(int index)`: from `_referee.legalUciMoves()`, keep those starting at
  `BoardHelper.squareName(index)` and map the target back with `BoardHelper.squareIndex`. Import
  `BoardHelper` from `package:ace/referee/rules/helpers/board_helper.dart`.
- `bool get whiteToPlay => _referee.whiteToMove;`
- `({int from, int to})? get lastMove`: from the last UCI in `uciHistory`.
- `move(int targetIndex)`: build the UCI from `_selectedIndex` → `targetIndex`. If a pawn moves to the last
  rank, add `'q'` (auto-queen, matching today's behaviour). Call `_referee.tryPlayUci`. If accepted,
  set `_gameEnd = _referee.checkGameEnd()` and then call `_aiMove()`.
- `_aiMove()`: `await _engine.getMove(_referee.startFen, _referee.uciHistory, SearchLimits(moveTime: Duration(milliseconds: _thinkingTime)))`,
  then `tryPlayUci`. If the engine throws or plays illegally, show a SnackBar/text instead of crashing,
  and log it with `debugPrint`.
- `startAIGame()` stays the same idea: the current engine plays both sides.

### 9.2 GUI changes (`lib/components/GUI.dart`)

- Replace `gameProvider.board.position[index]` → `gameProvider.pieceAt(index)`.
- Replace the legal-move highlighting loop with `gameProvider.legalTargetsFrom(selectedIndex).contains(index)`.
- `lastMove.startingSquare/targetSquare` → `lastMove?.from/to`.
- `isMoveValid` uses `legalTargetsFrom`.
- **Remove** `onDragComplete: () => gameProvider.board.position[index] = 0`. It mutates the board directly,
  and with the referee that isn't possible or needed. The provider moves the piece when the drop is accepted.
- Show the result with `gameProvider.gameEnd?.termination.name ?? 'playing'`.
- Add a version picker above the board:
  ```dart
  DropdownButton<String>(
    value: gameProvider.engineId,
    items: [for (final id in gameProvider.engineIds) DropdownMenuItem(value: id, child: Text('ACE $id'))],
    onChanged: gameProvider.engineThinking ? null : (id) { if (id != null) gameProvider.setEngine(id); },
  )
  ```
  Disable it while the engine is thinking. Changing the version starts a new game.

### 9.3 Clean-up

- Delete `lib/chess_engine/` and `lib/tests/tests.dart` (and the GUI's import of it).
- Delete `test/perft_test.dart` (now covered by `perft_all_versions_test.dart`).
- `Zobrist()` in `GameProvider` is gone, because each adapter and the referee initialise their own.
- Run `flutter analyze` and `flutter test`. Then run the app on your phone: play a game against v1,
  check castling, en passant, promotion, and that a mate shows the result.

**Done when:** the app has a dropdown listing `v1` (and later `v2`, `v3`…), and you can play each one.

---

## Phase 10: Your first experiment, v2 = v1 + bug fixes

1. `dart run tool/snapshot_engine.dart --from v1 --to v2`
2. In `lib/engines/v2/adapter.dart`, change `id`/`displayName` to `v2` / `ACE v2`.
3. Add `'v2': () => v2.AceEngine(),` to the registry.
4. Fix the bugs from §11 **inside `lib/engines/v2/` only**.
5. `flutter test` (perft and purity tests now cover v2 automatically).
6. Quick check: `--a v2 --b v1 --games 100 --movetime 20`.
7. Full run: `--a v2 --b v1 --games 1000 --movetime 100`.
8. Write the result down. A `match_results/README.md` or a table in the main README works:
   `v2 vs v1: +43.7 ± 18.6 (1000 games, 100ms)`.

### Example experiment: removing Zobrist hashing from a version

No engine has to use Zobrist. Only strings cross the interface. If you want a version without it
(e.g. `v3 = v2 − Zobrist`, a good experiment to measure what hashing is worth), remember what
depends on it inside the snapshot:

| Inside the engine                             | Uses Zobrist for                       | Without Zobrist                                                                                                                                                                                                                                                                                                                      |
| --------------------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Board.makeMove/unMakeMove`                   | updating `zobristKey` incrementally    | delete those lines and the `zobristKey` field                                                                                                                                                                                                                                                                                        |
| `Board.hashHistory` (repetition)              | counting how often a position occurred | Key by something else, e.g. the first 4 FEN fields (slow in search) or a list of piece arrays plus side/castling/ep compared on demand. **Or drop repetition detection.** Then the engine can't see draws coming, so it may walk into repetitions when winning and miss saving ones when losing. The referee still enforces the draw |
| `TranspositionTable`                          | keying entries                         | remove the TT (and the `entry` lookups/stores in `search`), or key it some other way                                                                                                                                                                                                                                                 |
| `MoveOrdering` (if it reads the TT best move) | ordering the TT move first             | just use the previous iteration's best move                                                                                                                                                                                                                                                                                          |
| `adapter.dart`                                | the `Zobrist()` init call              | delete it                                                                                                                                                                                                                                                                                                                            |

Then run the usual checks: perft (all of the above can break `unMakeMove` if done carelessly),
the purity test, a quick 100-game run, then the full match. Expect it to be **weaker**. The TT is a
big speed-up for iterative deepening. That's fine: the match tells you exactly how much weaker.

From then on: **one idea per version** (e.g. v3 = v2 + killer moves). Then you'll know which change
caused the gain or loss.

---

## 11. Known v1 bugs (leave v1 alone; fix them in v2)

Found while reading the code. Line numbers are as of commit `a26b7e1`.

| #   | Where                                                | Bug                                                                                                                                                                                       | Effect                                                                                                          | Fix in v2                                                                                                                                                                       |
| --- | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| B1  | `core/move.dart` `toChessNotation()`                 | Promotion piece not included (`e7e8` instead of `e7e8q`)                                                                                                                                  | Can't express underpromotion in UCI                                                                             | Append `'qnrb'[promotion-1]` when `promotion != 0`. (The adapter already works around this for v1.)                                                                             |
| B2  | `ai/engine.dart` lines 46–85                         | `print` every iteration and every move                                                                                                                                                    | Slows down search and floods output                                                                             | Remove, or put behind a `bool verbose = false`                                                                                                                                  |
| B3  | `ai/engine.dart` `search()` lines 97–100 and 158–161 | On timeout it calls `evaluation.evaluate(board);` and **throws the result away**, then keeps searching the node (TT probe, move generation…)                                              | Wastes time after the deadline and causes overruns                                                              | Replace it with `return 0;` (the value is ignored because the iteration is aborted). Also check `abortSearch` at the top                                                        |
| B4  | `ai/engine.dart` `quiescenceSearch()`                | Never checks the clock, only `abortSearch`                                                                                                                                                | Long capture sequences overrun `movetime`. You'll see this in "max ms" / "overruns"                             | Check the stopwatch every N nodes (e.g. `if (++qNodes & 1023 == 0 && stopwatch.elapsed >= maxDuration) abortSearch = true;`)                                                    |
| B5  | `ai/engine.dart` line 121                            | Draw check `board.hashHistory.values.any((e) => e >= 3)` asks whether **any** position in the history occurred 3 times, not the **current** one. It's also checked **after** the TT probe | Once any position in the game has hit 3, the engine thinks every node is a draw. The TT can also skip the check | `if (plyFromRoot > 0 && (board.hashHistory[board.zobristKey] ?? 0) >= 2) return 0;` (inside search, a single repeat is enough to score as a draw). Do it before the TT probe    |
| B6  | `core/board.dart` constructors                       | The starting position's hash is never added to `hashHistory`                                                                                                                              | A repetition of the start position is counted one short                                                         | Call `addMoveToHashHistory(zobristKey)` at the end of both constructors                                                                                                         |
| B7  | `helpers/fen_utility.dart` + `Board.fromFEN`         | The half-move clock is read into a field misnamed `plyCount` and never used. `fiftyMoveRule` is always 0. A FEN with only 4 fields crashes on `sections[4]`                               | The engine doesn't see the fifty-move rule approaching from mid-game FENs. 4-field FENs crash                   | Set `fiftyMoveRule = int.parse(sections[4])` when present (default 0), and parse the full-move number too                                                                       |
| B8  | `helpers/fen_utility.dart` `fenFromBoard()`          | Output has only 4 fields (no half-move/full-move)                                                                                                                                         | Other tools reject the FEN                                                                                      | Append `" $fiftyMoveRule ${gamePosition ~/ 2 + 1}"` (or track the full-move number properly)                                                                                    |
| B9  | `ai/transposition_table.dart` `retrieve()`           | Computes the mate-adjusted `eval` but returns `entry`, whose `eval` is unadjusted. `search()` then returns `entry.eval`                                                                   | Mate distances from the TT are wrong, and the engine can delay or miss the fastest mate                         | Return the adjusted eval (e.g. return an `int?` eval instead of the entry, or a copy with the adjusted eval). Make sure stores convert mate scores to "distance from this node" |
| B10 | `ai/engine.dart` root TT hit                         | At `plyFromRoot == 0` a TT hit sets `bestMoveThisIteration` but not `hasSearchedAtLeastOneMove`. It can also accept a bound (not exact) entry as the root result                          | Rare wrong or `null` root move                                                                                  | Skip the TT cut-off at the root (`if (plyFromRoot > 0 && entry != null)`)                                                                                                       |
| B11 | `ai/engine.dart` yield                               | `if (stopwatch.elapsedMilliseconds % 10 == 0) await Future.delayed(Duration.zero);` only yields when the ms count happens to be a multiple of 10                                          | The UI can stutter on the phone, and timing is irregular                                                        | Yield every N nodes instead (e.g. every 2048)                                                                                                                                   |
| B12 | `providers/game_provider.dart` `_getGameResult`      | The same "any position ×3" repetition bug, and `>= 100` vs the engine's `> 100`                                                                                                           | The app declares false repetition draws                                                                         | Goes away in Phase 9 (the referee replaces it)                                                                                                                                  |

> B1 and B2 are already handled for v1 by the adapter, so v1 still plays correctly in matches. B3–B11
> are real strength/correctness issues, so fixing them should give v2 a measurable Elo gain.
> That's a great first test that the match manager can detect improvement.

---

## 12. Side notes and future work (not now)

### Running games in parallel with isolates

- **What an isolate is:** a separate Dart "thread" with its **own memory**. Nothing is shared, so
  each isolate gets its own copy of every `static` (including Zobrist tables). Isolates talk by sending
  messages (`SendPort`/`ReceivePort`). The easy API is `Isolate.run(() => …)`, which runs a function in a
  new isolate and returns its result as a `Future`.
- **The plan when you're ready:** make the whole _game_ the unit of work. Write a top-level function
  `Future<GameRecord> playGameInIsolate(GameJob job)` where `GameJob` holds plain data (engine ids,
  opening FEN, move time, max plies, game number). Inside it, create the engines with
  `EngineRegistry.create` and call `GameRunner.playGame`. In `MatchRunner`, keep `K` jobs in flight
  (`K = Platform.numberOfProcessors - 1`) with a simple pool: start K, and each time one completes,
  record it and start the next. `GameRecord` must contain only plain data (it already does), so it can be
  sent back.
- **Speed-up:** roughly ×K. An 8-core laptop turns 3.3 h into ~30 min.
- **Caveat:** with K games at once each engine gets less CPU, so `movetime` means less search. Use
  `K ≤ physical cores − 1` and compare versions under the **same** K.
- **Bonus:** hard timeouts become possible. `Isolate.kill()` a game whose engine hasn't answered within
  `movetime × 3 + 1s`, and record it as `engineError` ("timeout"). That also fixes the "infinite loop
  hangs the match" problem.

### SPRT (stop early once the answer is clear)

Instead of fixed 1000 games, SPRT checks after each game whether there's enough evidence that the
new version is better by ≥ X Elo (or not). It typically stops after 100–500 games. Add
`--sprt elo0=0,elo1=10` later. The maths fits in about 40 lines.

### Other ideas

- A **UCI adapter** (`UciProcessEngine` implements `ChessEngine`, using `Process.start` + stdin/stdout) to
  test against Stockfish at a limited strength (`UCI_LimitStrength`, `UCI_Elo`) or other engines. Desktop only.
- **Gauntlets:** `--a v3 --b v1,v2`. Play the new version against every old one.
- **Increment clocks** instead of fixed movetime, once the engine has time management.
- **Eval-based adjudication** to shorten hopeless games (e.g. both engines agree on |eval| > 10 pawns for 5 moves).
- **Watch v1 vs v2 on the phone:** reuse `startAIGame()` with two engines, one per side.
- **A results history:** one line per completed match appended to `match_results/history.csv`.

---

## 13. Master checklist

- [ ] **P0**: baseline green, `getImg` moved out of `Piece`, `args` added, `match_results/` git-ignored, openings copied in
- [ ] **P1**: `engine_interface.dart`, `tool/snapshot_engine.dart`, `lib/engines/v1/` + `adapter.dart`, `EngineRegistry`, plus adapter/perft/purity tests
- [ ] **P2**: `lib/referee/rules/` copy + R1/R2 fixes, `San`, `Referee`, `GameEnd`, `RandomEngine`, plus SAN (incl. round trip), referee and rules perft tests
- [ ] **P3**: `PgnReader`, `OpeningBook`, plus tests. Your real file loads cleanly
- [ ] **P4**: `GameRecord`, `GameRunner`, fake engines, plus game tests
- [ ] **P5**: `MatchConfig`, `MatchRunner`, `elo.dart`, `MatchStats`, plus tests (Elo table)
- [ ] **P6**: `PgnWriter`, `MatchOutput`. PGN round-trips through your own `PgnReader` and imports into Lichess
- [ ] **P7**: `bin/match.dart` with progress, ETA and Ctrl-C handling. AOT build works
- [ ] **P8**: v1 vs random ≈ 100%, v1 vs v1 ≈ 0 Elo with zero errors
- [ ] **P9**: app uses Referee + ChessEngine, version dropdown works on the phone, `lib/chess_engine` deleted
- [ ] **P10**: v2 = v1 + §11 fixes, then a 1000-game v2 vs v1 run with the result written down
