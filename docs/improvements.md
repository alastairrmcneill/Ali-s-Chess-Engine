# Plan: search cleanup + reviewable game logs (no chess-logic changes)

Three independent, non-chess-logic improvements to `lib/engines/v1/ai/engine.dart` and the
match-manager output. None of these change move generation, evaluation, or search
algorithm/strength — only how the search is driven and what gets recorded about it.

## Current state (`lib/engines/v1/ai/engine.dart`)

- `getBestMove`, `runIterativeDeepening`, and `search` are all `async`, and `search` awaits
  itself recursively. The only reason for this: a line in the alpha-beta loop —
  ```dart
  if (stopwatch.elapsedMilliseconds % 10 == 0) {
    await Future.delayed(Duration.zero);
  }
  ```
  — yields to the event loop periodically so _something_ could interrupt it. But nothing
  ever does: `abortSearch` is only ever set by polling `stopwatch.elapsed` inside `search`
  and `getBestMove` itself, never by an external timer/callback. `Stopwatch.elapsed` is a
  real wall-clock read, independent of whether the isolate yields — so the periodic
  `await Future.delayed(Duration.zero)` buys nothing. It does cost something: every node
  pays for a `Future`/microtask per recursive call plus (10% of the time) a full event-loop
  round trip, which at the node counts this engine searches is a real, measurable slowdown.
- 8 `print(...)` calls fire during every single search: one per iterative-deepening depth
  (`"Starting with search of depth N"`, `"After searching with depth N:"`, best eval, best
  move), plus one final summary in `getBestMove`. Across a 1000-game match this is tens of
  thousands of lines to stdout, drowning out the match manager's own progress output and
  slowing the run down (console I/O is not free).
- Per-move diagnostics that _do_ survive today are thin: `EngineMoveResult` only carries
  `evaluation` and `nodes` (V1Engine never actually sets `depth`, even though `Engine` knows
  the final depth reached — `lib/engines/v1/v1_engine.dart`'s `getMove` just omits it). There
  is no record of the iteration-by-iteration search (what depth 1..N each concluded, how long
  each took, whether the final depth was a completed iteration or an aborted one), and no
  principal variation. `PgnWriter` already writes a short per-move comment
  (`+0.31/7 98ms`) from `MoveStat`, but that's the only place any of this is reviewable today,
  and it's limited to what `MoveStat` carries.

## 1. Remove the async/await from the search

**Goal:** `search`/`quiescenceSearch`/`runIterativeDeepening` become plain synchronous
functions. `getBestMove` can stay `Future<Move?>` (it's called from `V1Engine.getMove`, which
must stay `Future`-returning to satisfy `ChessEngine`), but its body does the search
synchronously and returns immediately — no `await` anywhere between "start search" and
"search done".

Steps:

- Delete the `if (stopwatch.elapsedMilliseconds % 10 == 0) { await Future.delayed(...); }`
  block from `search`. Time-based abort keeps working exactly as before: `search` and
  `getBestMove`/`runIterativeDeepening` already check `stopwatch.elapsed >= maxDuration`
  directly, and that check doesn't need an event-loop tick.
- Change `Future<int> search(...)` → `int search(...)`, drop `await` at its one recursive call
  site (`int moveEval = -1 * search(depth - 1, -beta, -alpha, plyFromRoot + 1);`).
- Change `Future<void> runIterativeDeepening()` → `void runIterativeDeepening()`, drop its
  `await search(...)` call.
- `getBestMove` can either drop `async`/`Future` entirely (becoming `Move? getBestMove(...)`)
  or keep the `Future<Move?>` signature with a synchronous body (no internal `await`) so
  `V1Engine.getMove` doesn't need to change at all. Keeping the `Future` signature is the
  smaller diff — prefer that unless a fully sync `Engine` API is wanted for its own sake.
- `quiescenceSearch` was already synchronous; no change needed there.

**Why this is safe:** nothing outside `Engine` calls `search`/`runIterativeDeepening`
directly, and `getBestMove`'s external signature doesn't have to change, so
`v1_engine.dart`, `engine_interface.dart`, and every caller are unaffected. Search behaviour
(nodes visited, moves returned, evals) is bit-for-bit identical — only the recursion
mechanics change from async to sync.

**Verification:** `perft_all_versions_test.dart` and the existing engine tests must still
pass unchanged (they don't depend on timing). Worth adding a quick benchmark (run
`getBestMove` at a fixed movetime before/after, compare `debugInfo.numNodes`) to confirm the
search explores _more_ nodes in the same wall-clock budget once the per-node await overhead
is gone — a nice side effect, not a goal.

## 2. Remove the console logging during search

**Goal:** zero `print()` calls from inside `Engine` during normal operation.

Steps:

- Delete all 8 `print(...)` statements in `getBestMove` and `runIterativeDeepening`
  (`lib/engines/v1/ai/engine.dart` lines ~46, 61, 74–76, 83–85).
- Nothing replaces them _in this class_ — the data they printed (best move/eval per depth,
  final node counts) is superseded by the structured logging in part 3 below, which captures
  the same information in a form that persists per-move instead of scrolling past in a
  terminal.

**Verification:** running a match (`dart run bin/match.dart ...`) should produce no engine
output at all — only the match manager's own summary lines. A simple test can assert this by
running a search inside `runZoned` / capturing `print` via `Zone` overrides and expecting zero
captured lines (useful as a regression guard so a future `print` added for debugging doesn't
silently ship again).

## 3. Structured per-move search logging (so a finished game can be reviewed)

**Goal:** after a match finishes, it should be possible to open one game and see, move by
move, what the engine was thinking — not just the move it played, but the depth it reached,
how the eval evolved across iterative-deepening iterations, and (if available) the line it
expected.

This needs changes at three layers: what `Engine` records per move, how that reaches
`GameRecord`, and how/where it's written to disk.

### 3.1 `Engine` records one `SearchLog` per `getBestMove` call

Add a small data class next to `DebugInfo` in `engine.dart`:

```dart
class SearchIteration {
  final int depth;
  final int eval;
  final Move? bestMove;
  final int elapsedMs;      // stopwatch.elapsedMilliseconds when this iteration completed
  final bool aborted;       // true if this iteration didn't finish before the time ran out
  const SearchIteration(this.depth, this.eval, this.bestMove, this.elapsedMs, this.aborted);
}
```

In `runIterativeDeepening`, instead of `print`-ing per depth, append a `SearchIteration` to a
`List<SearchIteration> lastSearchLog` field on `Engine` (reset at the top of `getBestMove`,
alongside `debugInfo`). This is a straight swap of "print this" for "record this" at the exact
two call sites that currently print per-depth info — no new control flow.

Expose the finished depth's principal variation too, if cheaply available: the transposition
table already stores `bestMove` per position, so a short PV can be reconstructed by walking
`transpositionTable.retrieve(...)` from the root a few plies deep after the search completes
(best-effort only — skip a position if the TT entry is missing/stale; this is read-only
diagnostics, never used to pick a move).

### 3.2 Carry the log out through `EngineMoveResult` → `MoveStat`

- Fix `V1Engine.getMove` to actually pass `depth` (the final completed iteration's depth,
  available from `_engine.lastSearchLog` or a new `_engine.bestDepth` field) — this is a
  one-line bug fix, not new logic, and `EngineMoveResult.depth` already exists on the
  interface but is silently always `null` from v1 today.
- Extend `EngineMoveResult` (`lib/engines/engine_interface.dart`) with an optional field for
  the rich log, e.g. `final List<SearchIterationSummary>? iterations;` and
  `final List<String>? principalVariation;`, using a small engine-agnostic summary type
  (plain ints/strings — not `Engine`'s internal `SearchIteration`/`Move`) so the interface
  stays engine-implementation-free. Both fields are optional/nullable: engines that don't
  produce this detail (fakes in tests, future simpler engines) just omit them.
- Extend `MoveStat` (`lib/match/game_record.dart`) with the same two optional fields, filled
  in by `GameRunner.playGame` from the `EngineMoveResult` exactly where it already builds
  `MoveStat` from `result.depth`/`result.nodes`/`result.evaluation` today.

### 3.3 Write it somewhere reviewable

`MoveStat`/`GameRecord` already flow into `PgnWriter`, which writes one short comment per
move into `games.pgn` — keep that as the "quick glance" view (still just eval/depth/time).
For the detailed per-iteration/PV view, add a sibling per-game log file written by
`MatchOutput`/`GameRunner` alongside the PGN:

- One line of JSON per game (JSON Lines), e.g. `game_0007.thinking.jsonl`, or a single
  `thinking.jsonl` with one line per _move_ across the whole match, tagged with
  `gameNumber`/`ply` — either is fine, pick whichever is simpler to append incrementally;
  since bin/match.dart no longer has a per-game hook (see the recent `MatchRunner` simplification
  noted in repo memory), this probably means `GameRecord` needs to carry the full per-move
  logs through to wherever games are eventually persisted, rather than being streamed out
  during the match — check how output is currently wired before picking the exact write
  point.
- Each line: `{"game": 7, "ply": 23, "side": "white", "move": "e2e4", "depth": 12,
"eval": 34, "nodes": 182341, "timeMs": 98, "iterations": [...], "pv": ["e2e4", "e7e5", ...]}`.
- This is additive and optional — omit the file entirely for engines that don't supply the
  richer fields, so games played by fakes/simple engines in tests don't need a dummy log.

**Verification:** a test engine (or `v1`) played for a few moves should produce a log file
where each entry's `depth`/`eval` lines up with the corresponding PGN comment for the same
move, and the file is valid JSONL (one `jsonDecode` per line succeeds).

## Suggested order of work

1. Part 1 (remove async) and part 2 (remove prints) first — small, independent, no new data
   structures, easy to verify with the existing test suite plus a quick manual match run.
2. Part 3 once 1–2 are done and verified, since it's additive and touches more files
   (`engine_interface.dart`, `game_record.dart`, `game_runner.dart`, and wherever per-game
   output is written) — recheck those files' current contents before editing, this codebase
   has been changing shape between sessions.
