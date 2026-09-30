# ACE v1: known issues

v1 is frozen in `lib/engines/v1/` exactly as it played in the app. Its search, evaluation, move ordering,
transposition table and move generator are unchanged. Only the FEN loading, which now uses the shared
`chess_core` parser, and the Flutter image code were touched. The issues below are left in on purpose, so each
fix can go into v2 and be *measured* with the match manager.

Line numbers refer to files in `lib/engines/v1/`.

Suggested order for v2: fix #1 first (it loses games outright), then #2–#4 (search correctness), then the rest.

## Measured in matches

Two v1 vs v1 self-play matches (240 games at 40–50 ms per move) were played while building the match manager:

- **v1 lost 11 of 240 games (4.6%) by playing an illegal move** (issue #1). The referee catches every one; they
  show up under "Games lost by illegal move" in `report.txt`.
- At 40–50 ms per move v1 reaches **depth 3 on average** (about 6,000 nodes per move). Its evals swing a lot between
  consecutive moves, so many moves get flagged as suspicious. Some of that is the shallow depth, and some is
  issues #2 and #3.
- v1 sometimes takes **about 2× its time budget** on a move (max ~105 ms at 50 ms per move). See #9.

## Move generation

### 1. Sliding pieces pass through pieces when blocking a check (plays illegal moves)
`core/move_generator.dart:381`. When in check, `generateSlidingMoves` does
`if (inCheck && !movePreventsCheck) continue;` *before* the `break` that stops a ray at the first piece it hits.
A rook, bishop or queen therefore keeps sliding past a piece that isn't on the check ray, and can "block" the check
from a square it can't really reach.

Example from a match: `6k1/1p2R1pp/p2qn3/5p2/3r4/P1Q5/1P3PPK/8 w - - 9 36`. White is in check from the queen on d6,
and v1 plays Re7-e5, jumping over the knight on e6.

- Found with perft: position 3 at depth 5 gives 674,630 instead of 674,624.
- A cross-check against python-chess over 77,003 random-game positions disagreed in 187 of them (0.24%), all
  from this bug.
- `test/engines/v1_engine_test.dart` pins v1's current (wrong) count, so the snapshot can't change by accident.
- **Fix:** `chess_core/move_generator.dart` has it. Only skip *adding* the move, and still `break` on a capture:
  ```dart
  if ((!inCheck || movePreventsCheck) && (isCapture || generateQuietMoves)) moves.add(...);
  if (isCapture || movePreventsCheck) break;
  ```

## Search (`ai/engine.dart`)

### 2. Aborted searches keep going and pollute the transposition table
- **Discarded eval on timeout.** Lines 97–100 and 158–161 compute `evaluation.evaluate(board)` when time runs out,
  but throw the result away. The search doesn't return; it carries on until the loops notice `abortSearch`.
- **Partial results stored as exact.** After an aborted loop (`if (abortSearch) break;`, line 145), the node still
  stores `alpha` in the TT (line 198) as if it had been fully searched. The type is `exact` if any move raised alpha.
  Those half-searched scores are then trusted by later probes at the same or lower depth in the same search.
- **Fix:** when `abortSearch` is set, return immediately (e.g. `return 0`) and never write TT entries for aborted
  nodes. The root already discards unfinished iterations except for `bestMoveThisIteration`.
- **Likely symptom seen in a match:** in `6k1/5rp1/3NQ3/4p1bp/P7/5qP1/1P5P/4R1K1 w - - 5 49`, v1 played Rxe5,
  reporting `+5.15/3` with the line `Rxe5 Bc1 Qc8+ Rf8`, and was mated by Qf1# straight after. A completed depth 3
  search must see a mate-in-one reply, so a bad score reached the root. A partial iteration or a polluted TT entry
  (this issue, or #3) is the likely cause. `bin/inspect.dart` on that position ranks Rxe5 last, at #-1. It's a good
  regression position for v2.

### 3. Mate scores in the transposition table aren't adjusted for distance
`ai/transposition_table.dart:25–29`. `retrieve` computes an adjusted `eval` with `adjustMateScore`, but then returns
the original `entry` (with the unadjusted `entry.eval`), and `engine.dart:111` uses `entry.eval`. Mate scores are
also stored without converting them to "mate from this node" (lines 165–173 and 198–206). So a mate found through a
transposition reports the wrong distance, and can prefer slower mates or misjudge them.
- **Fix:** when storing, add `plyFromRoot` to positive mate scores (subtract it from negative ones). When
  retrieving, do the reverse and return the adjusted value.

### 4. Draw detection happens after the TT probe and looks at the wrong position
- **Probe before draw check.** The TT is probed (line 103) before the repetition / 50-move check (line 121). A
  position that is now a draw by repetition can return a stored non-draw score.
- **Wrong position checked.** `board.hashHistory.values.any((element) => element >= 3)` checks whether *any*
  position in the game has occurred three times, not the current one.
- **Needs three occurrences.** It also needs three occurrences inside the search. Engines normally treat a single
  repeat within the search tree as a draw, so they can see repetitions coming.
- **Fix:** check `hashHistory[board.zobristKey] >= 2` (plus the 50-move rule) before probing the TT, skipping the
  root.

### 5. Move ordering uses the root's best move everywhere
`engine.dart:127` passes `bestMove` (the root's best move from the previous iteration) to `orderMoves` at *every*
node. The move stored in the TT for the current position is never used for ordering, which is where most of the TT's
value comes from.
- **Fix:** probe the TT for the node's `bestMove` and put it first.
- **Slow sort.** `ai/move_ordering.dart:10–12` recomputes both move scores inside the sort comparator (O(n log n)
  score calls). Scoring each move once into a list and sorting that is faster.

### 6. `search` is `async` at every node
`engine.dart:95` makes every node return a `Future`, so each of the millions of nodes allocates futures and goes
through the event loop. This is likely the single biggest cost in v1's speed (depth ~3 at 50 ms).
- **Current yield is irregular.** It yields with `if (stopwatch.elapsedMilliseconds % 10 == 0)` (line 192), which
  only happens when the millisecond count happens to be a multiple of 10 at that moment.
- **Fix:** make `search` synchronous and check the clock every N nodes. Matches run engines on background isolates,
  so the UI doesn't need the engine to yield. The store app can run the engine with `Isolate.run`.

### 7. The TT is cleared every move and grows without limit
`engine.dart:34` clears the table at the start of every move, throwing away work from the previous search. The table
is a `Map` with no size cap (`ai/transposition_table.dart:4`), so memory grows with search time.
- **Fix:** a fixed-size list indexed by `zobristKey % size`, kept between moves (clear it in `newGame`).

### 8. No move is returned if depth 1 doesn't finish
If time runs out before any root move finishes searching, `bestMove` stays `null` (line 54). At very short think
times this makes v1 return nothing, which the match manager scores as a loss.
- **Fix:** start with the first legal move as a fallback.

### 9. Quiescence search ignores the clock, checks and mates
`quiescenceSearch` only stops on `abortSearch` (line 216), which is only set in `search`. A long capture sequence
therefore isn't cut off, which is likely part of why moves overrun their time (a cold start on a new isolate is
the other part). It also stands pat while in check, and
never detects checkmate or stalemate.
- **Fix:** check the clock (or a node counter) in quiescence too. When in check, search all evasions instead of
  standing pat.

## Board

### 10. The starting position doesn't count towards repetition
`core/board.dart` only adds positions to `hashHistory` in `makeMove` (line 196), so the position a game starts from
is never counted.
- **Fix:** add the initial position when a board is created (done in `chess_core/board.dart`).

### 11. Zobrist keys must be created manually, and are re-randomised on every call
`core/zobrist.dart:25`. Keys are all zero until `Zobrist()` is constructed. Constructing it again re-randomises every
key, which silently breaks the hashes of any existing board. `V1Engine` works around this by constructing it once
per isolate.
- **Fix:** static keys created on first use (done in `chess_core/zobrist.dart`).

## Smaller things

- **Wasted board.** `MoveGenerator()` builds a full `Board()` just to initialise itself.
- **No promotion letter.** `Move.toChessNotation()` in v1 leaves out the promotion piece (`e7e8` instead of `e7e8q`).
  The adapter uses its own conversion.
- **Dead code.** `Piece.print` calls `string.toUpperCase()` without using the result (it's unused).
