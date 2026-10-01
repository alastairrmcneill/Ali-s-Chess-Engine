# Plan: Engine Match Manager (v1 vs v2 vs …) in Dart

## Context

ACE v1 is working and shipped. The next step is iterating on it (v2, v3, …), and each new version needs proof that it's actually stronger. Sebastian Lague's approach is used as the model: freeze old versions, play ~1000 games between two versions from a set of balanced opening positions (each opening played twice with colours swapped), and read off the score/Elo difference.

Today that isn't possible:

- There's one `Engine` bound to one `Board` (`lib/chess_engine/ai/engine.dart`).
- The FEN loader can't load arbitrary positions: en passant parsing is commented out and the half-move clock goes into the wrong field.
- Game-over rules live in `GameProvider` (UI layer).
- The engine runs on the UI isolate and prints on every iteration.
- `piece.dart` imports Flutter, so the engine can't run from a plain `dart run` CLI.

**Decisions made with the user:**

- Frozen snapshot folder per version.
- Runs on the phone (dev-only entry point) **and** from a desktop CLI.
- Fixed time per move.
- ~500 openings sampled from Stockfish's CC0 balanced book, ×2 colours = 1000 games.
- Output: score + Elo ± error, live board, PGN with per-move engine info, suspicious-move report, and a position inspector (top-N moves) included in this build.
- Engines talk via FEN + UCI move strings, so a Stockfish/UCI adapter can be added later.
- v1 is frozen with its search/eval untouched. Only non-engine bugs (FEN loading, etc.) are fixed. Engine bugs go into a doc for v2.

## Target layout

```
lib/
  chess_core/        referee + tooling (maintained, fixable). Moved from lib/chess_engine/core + helpers
  engines/
    chess_engine.dart     interface: ChessEngine, EnginePosition, SearchLimits, SearchResult
    engine_registry.dart  {'v1': () => V1Engine()}; `latestEngineId`
    v1/                   frozen snapshot of today's board, move gen, search and eval + v1_engine.dart adapter (FEN/UCI parsing comes from chess_core)
  match/             game_runner, match_runner (isolate pool), match_stats, pgn (write+parse), report, opening_book_data.dart
  analysis/          position_inspector.dart
  match_ui/          dev screens (setup, live, results, saved matches, game viewer, inspector)
  main.dart          store app (behaviour unchanged)
  main_match.dart    dev entry: `flutter run -t lib/main_match.dart`
bin/match.dart, bin/inspect.dart           desktop CLI
tool/build_opening_book.dart, tool/new_engine_version.dart
docs/engine_v1_known_issues.md, docs/match_manager.md
```

Everything under `chess_core/`, `engines/`, `match/` and `analysis/` must stay Flutter-free. A guard test enforces this.

## Phase 1: Core split, v1 snapshot, engine interface

**Shared vs per-engine rule:** anything defined by the chess standards lives once in `chess_core` and every engine version uses it:

- FEN parsing and writing
- UCI move-string parsing
- SAN/PGN
- Game rules and result detection

Each version owns its board representation, move generator, search and eval. It also owns a thin mapping from the shared parsed types into its own `Board`/`Move`, because that mapping depends on the board representation (e.g. a future bitboard v3).

1. **Create `lib/chess_core/`** from the current `core/` + `helpers/` (`git mv` so history follows), then fix and extend it:
   - `fen.dart`: parses a FEN into a neutral `FenPosition` (64-square piece list, side to move, castling rights, en passant square, half-move clock, full-move number). The en passant and clock parsing bugs are fixed here. It can also write a FEN, with the en passant rank bug fixed and the clocks included.
   - `Board.fromFen`. Count the initial position in `hashHistory`.
   - `uci.dart`: parses `"e7e8q"` → neutral `(from, to, promotion)`. It also converts core `Move` ↔ UCI, inferring flags (castling/en passant/double push/promotion) from the board.
2. **Snapshot v1.** Copy `lib/chess_engine/**` → `lib/engines/v1/**`, rewriting imports to `package:ace/engines/v1/...`. Only non-engine changes are allowed:
   - Remove v1's own FEN loading code; `Board.fromFen(fen)` uses the shared `chess_core` parser and maps `FenPosition` into v1's board fields.
   - Add a UCI → v1 `Move` mapping in the adapter, using the shared UCI parser.
   - Drop `Piece.getImg` and the Flutter import.
   - Search/eval/TT/move ordering/move gen stay byte-for-byte the same.
   - `san.dart`: SAN write (disambiguation, `+`/`#`, `O-O`, `=Q`) and SAN parse (match against the legal moves' SAN).
   - `game_result.dart`: extracted from `GameProvider._getGameResult` (`lib/providers/game_provider.dart:152`). Repetition is fixed to check the _current_ position's count. Adds a max-length adjudication.
   - Move `Piece.getImg` to `lib/components/piece_image.dart`. `square.dart` uses it.
3. **Interface** (`lib/engines/chess_engine.dart`), mirroring UCI so a process-based UCI engine can implement it later:
   ```dart
   abstract class ChessEngine { String get id; String get name; void newGame();
     Future<SearchResult> search(EnginePosition pos, SearchLimits limits); }
   class EnginePosition { String startFen; List<String> uciMoves; }   // like `position fen … moves …`
   class SearchLimits { int moveTimeMs; }                              // like `go movetime`
   class SearchResult { String? bestMove; int? scoreCp; int? mateIn; int? depth; int? nodes; List<String> pv; int timeMs; }
   ```
4. **`V1Engine` adapter** (`lib/engines/v1/v1_engine.dart`) wraps the untouched v1 `Engine`:
   - Initialises v1 `Zobrist` once per isolate. Today, hashes are silently all 0 if it's never initialised.
   - Builds a v1 `Board` from `startFen` and replays the moves, so v1 sees the repetition history.
   - Calls `getBestMove` inside a `Zone` that swallows prints. It parses v1's own "After searching with depth N" lines to report depth, with no engine edit needed.
   - Eval comes from `bestEval` (mate scores converted to mate-in-N). Nodes come from `debugInfo`.
   - The expected line (PV) is read by walking the TT's exact entries after the search.
   - If v1 returns a null best move, the result is null and the referee handles it.
5. **Rewire the store app.** `GameProvider` uses `chess_core` for the board/rules/UI and calls the engine through `ChessEngine` (`engineRegistry[latestEngineId]`) with FEN + UCI moves. Behaviour is unchanged for players.
6. Delete `lib/chess_engine/` and `lib/tests/tests.dart`, whose perft moves into real tests. Replace the broken default `test/widget_test.dart` counter test with an app smoke test.

## Phase 2: Opening book

- Download `8moves_v3.pgn.zip` from `official-stockfish/books` (CC0; 34,700 balanced 16-ply lines).
- `tool/build_opening_book.dart` parses the PGN with `chess_core` SAN, samples 500 lines with a fixed seed, and writes `lib/match/opening_book_data.dart` (a `const List<String>` of UCI move lines).
- A Dart source file (not an asset) works in both the app and the CLI. The attribution comment is kept in that file.
- Games start from the normal start position with the 16 book plies forced, so PGNs show the full game and repetition history is correct. Opening _i_ is always the same across matches, so v2-vs-v1 and v3-vs-v1 runs are comparable.

## Phase 3: Match engine (pure Dart) and CLI

- **`game_runner.dart`**, `playGame(opening, whiteId, blackId, moveTimeMs, maxPlies)`:
  - Applies the book moves, then loops: check the result → ask the side to move → validate the returned UCI move against `chess_core` legal moves → apply.
  - Records per move: SAN, UCI, eval, depth, nodes, time, PV.
  - An illegal or null move loses the game. Time overruns (> 1.5× movetime + 50 ms) are flagged in the report rather than forfeited.
  - Terminations: mate, stalemate, threefold, 50-move, insufficient material, illegal move, max length (default 500 plies → draw).
- **`match_runner.dart`**: an isolate pool (`Isolate.spawn`, default concurrency = cores − 1).
  - Jobs are `(openingIndex, whiteId, blackId)`, with each opening played twice with colours swapped. Engines are built inside the worker from the registry id.
  - A stream emits game results, plus per-move FENs for one "featured" game (the live board).
  - Graceful stop. Per-engine movetime overrides (`--movetime2`) allow handicap/calibration runs.
- **`match_stats.dart`**:
  - W/D/L and score.
  - Elo = −400·log10(1/s − 1), with a 95% CI computed over game _pairs_ (pentanomial-style, which fits the colour-swapped pairs).
  - Likelihood of superiority. Termination breakdown. Average depth, nodes and move time per engine.
- **Suspicious moves** (`report.dart`):
  - Flags a move when the mover's own eval drops ≥ 150 cp by its next turn, i.e. it missed the reply. Only counted when the mover wasn't already lost.
  - Also flags games lost after the engine reported ≥ +3.00.
  - Output is a list sorted by swing (game #, ply, FEN, before/after eval). Flagged moves get a `?` NAG in the PGN.
- **`pgn.dart`**:
  - Writer: headers (White/Black = engine names, Round, Result, Termination, `[MoveTime]`, `[Opening "book #n"]`), book moves as `{book}`, and engine moves annotated cutechess-style: `{+0.45/7 98ms 41k nodes; pv: Nf3 Nc6 Bb5}`. Eval is from the engine's perspective.
  - Parser: reads these files back for the inspector/viewer.
- **Output folder** `matches/<date>_<A>_vs_<B>/` containing `games.pgn`, `summary.json` (stats + suspicious list) and `report.txt`. `matches/` is added to `.gitignore`.
- **`bin/match.dart`** (uses the `args` package), e.g. `dart run bin/match.dart --engine1 v2 --engine2 v1 --games 1000 --movetime 100 --concurrency 3`. Prints a live line like `[312/1000] v2 +118 =150 -44 | +82 ± 30 Elo`, then the report.

## Phase 4: Phone match manager (dev entry only)

`lib/main_match.dart` → `lib/match_ui/`. The store app's `main.dart` is untouched.

- **Setup:** engine A/B dropdowns (from the registry), games, movetime, concurrency.
- **Running:**
  - Progress bar, live W/D/L + Elo ±.
  - Live board of the featured game, reusing `Square` + `piece_image.dart` in a read-only `BoardView`.
  - Stop button. The screen is kept awake with `wakelock_plus`.
- **Results:** summary, terminations, suspicious-move list (tap → game viewer at that ply), and a share-PGN button (`share_plus`).
- **Saved matches:** saved to the app documents dir (`path_provider`), in the same file format as the CLI.

## Phase 5: Position inspector

- **`position_inspector.dart`**: `analyse(engineId, startFen, uciMoves, topN, msPerCandidate)`.
  - For each legal move: if the move ends the game, the referee scores it directly. Otherwise it asks the engine to search the resulting position and negates the eval.
  - Sorts the results and returns the top N with eval, depth and expected line.
  - Treats the engine as a black box, so it works for every version with no engine changes. It also shows what the engine actually played in the match and its logged info.
- **Phone:** game viewer (board, step ◀ ▶, move list with comments). "Inspect position" chooses an engine version, N and time per candidate, and shows results with a progress indicator. Tapping a candidate previews its line.
- **CLI:** `dart run bin/inspect.dart --engine v1 (--fen "…" | --pgn games.pgn --game 12 --ply 34) --top 5 --movetime 300`.

## Phase 6: Docs and workflow tooling

- **`docs/engine_v1_known_issues.md`.** Each issue is verified while writing it up, with file:line references. Candidates found so far:
  - The timeout branch computes an eval and discards it, and aborted partial results still get written into the TT (`engine.dart:97-100, 158-161, 198`).
  - The TT is probed before the repetition/50-move check.
  - Mate-score ply adjustment is computed but never applied (`transposition_table.dart:25-29`, stored unadjusted).
  - Repetition checks whether _any_ history position has hit 3, not the current one.
  - Move ordering uses the previous iteration's root best move at every node rather than the TT move. Scores are recomputed in the sort comparator.
  - `search` is `async` at every node (Future overhead) and yields irregularly (`elapsedMilliseconds % 10 == 0`).
  - The TT is cleared every move and has no size limit.
  - A null best move is possible at very short movetimes.
  - Board-level: the start position isn't counted for repetition. `Zobrist()` re-randomises on every construction and gives all-zero keys if never called.
  - Plus any perft failures of v1's move generator found in Phase 1.
- **`docs/match_manager.md`:** running on phone/CLI, reading the report and PGN comments, the engine interface contract, and how to create a new version.
- **`tool/new_engine_version.dart v2`:** copies `lib/engines/<latest>` → `lib/engines/v2`, rewrites imports, renames the adapter and registers it.
- **README:** short section linking to the docs.

## New dependencies

- `args` (CLI)
- `path_provider`, `share_plus`, `wakelock_plus` (dev match UI)
- `test` if needed beyond `flutter_test`

## Verification

Install the Flutter SDK (matching the `.metadata` stable revision, or the closest compatible stable) in the scratchpad, then run:

1. `flutter analyze` is clean, and `flutter test` passes:
   - FEN round-trips (en passant, clocks).
   - UCI conversion (castle/en passant/promotion).
   - SAN write and parse.
   - Perft on `chess_core` for the start position, Kiwipete, and chessprogramming.org positions 3–5 (shallow depths so it runs quickly).
   - Game-result cases.
   - Elo maths against known values (55% → ≈ +35 Elo).
   - PGN write → parse round-trip.
   - The no-Flutter-import guard.
   - A smoke match (v1 vs v1, 4 games, 20 ms, concurrency 2).
   - Perft is also run on the v1 snapshot, and any failures are documented rather than fixed.
2. `dart run bin/match.dart --engine1 v1 --engine2 v1 --games 40 --movetime 50` should give roughly 50% with a CI that includes 0.
3. Handicap sanity check: `--movetime 20 --movetime2 200` (same engine). The side with more time should win clearly with a positive Elo outside the CI. This proves the stats detect a real difference.
4. `bin/inspect.dart` on a mate-in-1 FEN should list the mating move first. On a position from a generated PGN it should return N sorted candidates.
5. Open a generated `games.pgn` and check that the headers, comments and results look right. The user can confirm on the phone with `flutter run -t lib/main_match.dart`, since no device is available here.

## Delivery

- Commit per phase on branch `claude/funny-fermat-5hk7wz` and push.
- No PR unless requested.
