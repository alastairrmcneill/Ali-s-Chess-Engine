# v11 — Speed Improvements: Build-It-Yourself Plan

Scope: `lib/engines/v11/`. Five pieces of work, ordered so each one is small, testable and
measurable before the next starts.

| Phase | Work | Effort | Expected gain |
|---|---|---|---|
| 0 | Benchmark harness and baseline | Low | Needed to prove everything else |
| 1 | Delta pruning in quiescence | Low | Medium |
| 2 | Remove `isInCheck()` and the double movegen in Q-search | Low–Med | Medium–High |
| 3 | Better move ordering (killers, history, attacked-square penalty, checks) | Medium | High |
| 4 | Piece lists on the board | Med–High | High |
| 5 | Incremental material, PST and phase scores | Med–High | Highest |

The old "ints instead of lists for counters" item is skipped. Phase 5 deletes those per-call lists
entirely, so converting them first would be wasted work.

---

## Background (read first)

1. **Quiescence search.** After `depth == 0`, `searcher.dart:189` keeps searching captures until
   the position is "quiet", using a stand-pat score as a lower bound. Delta pruning and the check
   handling both live here.
2. **Why the evaluator is the hot spot.** `evaluate()` (`evaluator.dart:45`) scans all 64 squares
   and allocates seven 2-element lists on every call. It runs at every Q-node, and Q-nodes are most
   of your nodes (see `stats.qNodes`).
3. **Why movegen is the other hot spot.** `generateLegalMoves` (`move_generator.dart:66`) calls
   `init()`, which allocates nine lists and three sets, then `findPieces()` scans 64 squares.
4. **Killer and history heuristics.** Look both up on the Chess Programming Wiki before Phase 3.

---

## Phase 0 — Benchmark harness and baseline

Without numbers you can't tell a speed-up from noise or a bug.

1. Pick 6–10 FENs: the start position, a few middlegames (open and closed), a tactical position, a
   king-and-pawn endgame, and one position that is in check at the root.
2. Write a small script (e.g. `tool/bench_v11.dart`) that, for each FEN, runs
   `Searcher.getBestMove(board, depth: N)` with a fixed depth (start with 6; adjust so the whole
   suite takes ~30 s). Print per position: best move, eval, `stats.nodes`, `stats.qNodes`,
   `stats.betaCutoffs`, `stats.firstMoveCutoffs`, elapsed ms. Print totals at the end.
3. Fixed depth, not fixed time. Fixed depth makes node counts comparable between versions. Nodes per
   second shows raw speed. Total time to depth shows overall gain.
4. Record the baseline in a table at the bottom of this file ("Results log").
5. Run perft on a handful of positions (start, Kiwipete, a position with en passant and
   promotions). Record the node counts. You will re-run this after Phases 2 and 4 to prove move
   generation is unchanged. Check whether a perft helper already exists in the repo first.

**Done when…**

- [x] The benchmark runs in one command and prints a totals line.
- [x] Baseline numbers are in the Results log.
- [x] Perft passes against known values.

**How it was built**

- `tool/bench_v11.dart`: 10 FENs, fixed depth (default 7, about 15 s; depth 8 is about 2 min).
  Run it with
  `dart compile exe tool/bench_v11.dart -o $TMPDIR/bench_v11 && $TMPDIR/bench_v11 --perft`.
  Use AOT, since `dart run` (JIT) gives noisy, slower numbers. Flags: `--depth N`, `--perft`, `--only <substring>`.
- Perft already existed: `V11Engine.perft` and `test/engines/perft_all_versions_test.dart`. The bench
  re-uses `V11Engine.perft` with 4 known cases (node *and* capture counts) and prints PASS/FAIL, so
  it is a quick check after Phases 2 and 4. Run the full test file for the deep ones.
- Node counts are deterministic (fresh `Searcher`, fresh TT per position). Time is not, so run
  twice and take the lower figure when comparing nps.

> Rule for every phase below: run the benchmark and perft, add a row to the Results log, and only
> then commit. Two kinds of change are expected:
> - **Pure speed-ups** (Phases 2, 4, 5 if done correctly) must give the **same best moves and same
>   node counts**. If node counts change, there is a bug or a behaviour change to explain.
> - **Search changes** (Phases 1, 3) change node counts on purpose. Check the best moves are
>   sensible and that depth-to-time improved.

---

## Phase 1 — Delta pruning in quiescence

### Idea
After stand pat, if even winning the most valuable thing available cannot lift the score to alpha,
the capture cannot help. Skip it.

```
if (!inCheck && standPat + capturedValue + margin < alpha) continue;
```

### Steps

1. **Piece values.** `Evaluator.pieceValues` (`evaluator.dart:31`) is indexed by `Piece.type`. Use
   it for the captured value (en passant captures a pawn, but the target square is empty, so special
   case it). For promotions add `pieceValues[queen] - pieceValues[pawn]`.
2. **Know whether we're in check.** After Phase 2 you'll have this flag from the generator. Until
   then you can do Phase 1 using the existing `inCheck` local at `searcher.dart:199`. Never prune
   when in check: stand pat isn't valid there.
3. **Per-move delta.** Inside the move loop at `searcher.dart:223`, compute `gain` for the move and
   `continue` if `standPat + gain + deltaMargin < alpha`. Start with `deltaMargin = 200`.
4. **Optional whole-node delta.** Before generating moves, if `standPat + 900 + margin < alpha` (no
   capture, even a queen, can help), return `alpha` immediately. Keep this separate and measure it
   separately.
5. **Endgame guard.** Material swings matter most when little material is left. Consider turning
   pruning off when the midgame phase is very low (e.g. under 4). Test with and without.
6. Make `deltaMargin` a field so you can tune it quickly (try 100, 200, 300).

### Watch out
- `standPat` must be kept in a variable that is still in scope at the move loop. Right now it is
  declared inside the `else` block at line 211.
- Don't prune promotions with a plain pawn-capture gain.

### Done when…
- [ ] `qNodes` drops noticeably on the benchmark.
- [ ] Best moves on the tactical positions are unchanged.
- [ ] Margin tuned and recorded in the Results log.

---

## Phase 2 — Remove `isInCheck()` and the double movegen in Q-search

### Problem
`quiescenceSearch` (`searcher.dart:198-218`) does this at every node:

1. `moveGenerator.isInCheck(board)`: an `indexWhere` over the board to find the king, then ray walks.
2. If in check and too deep for evasions: full `generateLegalMoves` just to test for mate...
3. ...then `generateLegalMoves(includeQuietMoves: false)` again for captures.

`generateLegalMoves` already computes `inCheck` itself (`generateOpponentAttackData`), so step 1 is
redundant work.

### Design
Make the generator able to decide "give me evasions if in check" in a single pass.

1. **Add an evasion mode.** In `generateLegalMoves`, after `generateOpponentAttackData()`, add:
   ```dart
   if (inCheck) generateQuietMoves = true; // evasions can be quiet
   ```
   so a captures-only request still returns every legal evasion when in check. Be careful:
   `generateQuietMoves` is also a field set from the parameter at the top of the call, so restore or
   re-derive it per call (it is reset on every call, so this should be fine, but check).
2. **Add a captures-only filter helper** for the "in check but too deep" case: keep moves where
   `board.position[move.to] != Piece.none || move.promotion != 0 || move.enPassantCapture`.
3. **Rewrite the top of `quiescenceSearch`:**
   - `moves = generateLegalMoves(board, includeQuietMoves: false)`; `inCheck = moveGenerator.inCheck`.
   - If `inCheck` and `moves.isEmpty` → return `mateScore + plyFromRoot`.
   - If `inCheck` and `qDepth < qCheckDepthLimit` → no stand pat; search all `moves`.
   - Otherwise → stand pat (cutoff / raise alpha); if `inCheck` filter `moves` to captures only.
4. **Copy `inCheck` into a local immediately.** `moveGenerator` is a shared object. The recursion
   overwrites its fields, so read `inCheck` before the loop.
5. **Beware of the shared `moves` list.** `generateLegalMoves` returns `this.moves`, which is
   replaced by `init()` on the next call (`moves = []`), so the recursion doesn't corrupt the loop.
   Confirm this stays true.
6. **Stalemate in Q-search.** Q-search in a non-check position with no captures is not stalemate
   (quiet moves exist). Don't add stalemate detection there. That behaviour is unchanged.

### Behaviour to preserve
A position in check past the limit must still return mate when no evasions exist, and must still
stand pat otherwise. Node counts and best moves should match the baseline exactly, apart from
removing the second movegen. If they differ, you changed behaviour somewhere.

### Done when…
- [ ] `isInCheck` is no longer called from Q-search. (Delete it if nothing else uses it:
      `grep -rn isInCheck lib/engines/v11`.)
- [ ] Perft unchanged, benchmark best moves and node counts unchanged.
- [ ] nps up. Record in the Results log.

---

## Phase 3 — Better move ordering

Currently (`move_ordering.dart:38`) the score is: TT move → 10000, promotion bonus, and MVV-LVA for
captures. All quiet moves score 0, so their order is arbitrary. Better ordering means more beta
cutoffs on the first move. Track `stats.firstMoveCutoffs / stats.betaCutoffs` as your success metric.

### Target ordering (highest first)
1. TT move
2. Winning/equal captures (MVV-LVA), promotions
3. Killer moves (quiet moves that caused a cutoff at this ply)
4. Quiet checks (small bonus)
5. Quiet moves by history score, with an attacked-square penalty
6. Losing captures (optional, later)

### 3a — Plumb ply and tables through
- `scoreMoves(board, moves, scores, {ttMove})` needs the ply, the killer table and the history
  table. Add them as parameters, or put the tables inside `MoveOrdering` (preferred: it already
  lives on `Searcher`) with `scoreMoves(..., {required int ply})`.
- `MoveOrdering` fields: `List<Int32List> killers` (size `[maxPly][2]`) and
  `Int32List history` sized `2 * 64 * 64` (colour, from, to).
- Reset history at the start of `getBestMove`. Killers can be reset or aged between searches.

### 3b — Killer moves
- A killer is a **quiet** move that caused a beta cutoff.
- On cutoff in `search()` (`searcher.dart:171`): if the move is not a capture and not a promotion,
  and it is not already `killers[ply][0]`, shift slot 0 → slot 1 and store the move in slot 0.
- Scoring: a killer gets a score above all quiets but below good captures (e.g. 9000 vs MVV-LVA
  captures that start at ~100+ — pick numbers so the bands can't overlap; write them as named
  constants).
- Don't store killers from Q-search.

### 3c — History heuristic
- On a quiet-move cutoff: `history[color][from][to] += depth * depth`.
- Optional but recommended: for each quiet move tried *before* the cutoff move at that node, apply a
  penalty (`-= depth * depth`) so history stays discriminating.
- Clamp or age values (e.g. halve all entries when one exceeds a limit) so they can't overflow the
  band you reserved for quiets.
- Quiet score = `history[...]`, bounded below the killer band.

### 3d — Attacked-square penalty (the "attacks" idea)
- Moving a piece onto a square the opponent already attacks usually loses it.
- The generator already builds `opponentAttackMap` (`Set<int>`, `move_generator.dart:22`). Options:
  - **Cheap:** expose it from the generator and, for quiet moves, subtract
    `pieceValue(mover)` (small scale) if `opponentAttackMap.contains(move.to)`. Remember that the map
    is rebuilt by the *next* `generateLegalMoves` call, so score moves **before** recursing. That
    is already the order in `search()`.
  - **Better but more work:** pawn attacks only (a piece moving onto a pawn-attacked square is
    nearly always bad), or SEE. Do only if cheap version shows gain.
- Also optional: a small bonus for moving a piece *off* an attacked square.
- Note `opponentAttackMap` includes squares of opponent pieces only as "attacked" when sliders pass
  through; it's an attack map, not a defended map. That's fine for this heuristic.

### 3e — Check bonus
- A move gives check if after it the opponent king is attacked. Options, from cheapest:
  1. **Direct check by piece type.** Precompute, per move, whether `to` attacks the opponent king
     for the moved piece: knight (`knightMoves[to]` contains king), pawn (`pawnCaptures[to]`
     contains king), sliders (are `to` and king aligned with nothing between, using
     `directionOffsets` and `numSquaresToEdge`). This misses discovered checks, which is OK for
     ordering.
  2. **Make, test, unmake.** Exact but slow. Not recommended.
- Only apply to quiet moves in the main search (and not at all in Q-search for now).
- Keep the bonus smaller than any capture, larger than history.
- Consider later: check extensions in `search()`. That is a search change, not ordering. Keep it out
  of this phase.

### 3f — Housekeeping
- `orderMoves` (root) uses `sort` with scores recomputed in the comparator. It runs once per
  search, so it doesn't matter for speed. Leave it, or switch it to precomputed scores.
- Replace magic numbers with named constants in one block at the top of the file, with a comment
  showing the bands.

### Done when…
- [ ] `firstMoveCutoffs / betaCutoffs` ratio is up.
- [ ] Total nodes to a fixed depth is down.
- [ ] Each sub-step (3b, 3c, 3d, 3e) was added and measured separately, with a row in the Results
      log. Keep only what helps.

---

## Phase 4 — Piece lists on the board

### Problem
Both `MoveGenerator.findPieces()` and `Evaluator.evaluate()` scan all 64 squares every call and
sort pieces into lists. The board already knows what it contains, but only as a flat `position`
array.

### Design
In `Board`, keep, for each colour and piece type, the squares where that piece type stands.

```dart
// index: colorIndex * 8 + pieceType   (type 1..6; pad to 8 for a cheap shift)
final List<Int32List> pieceSquares;   // each Int32List(10) — max pieces of a type incl. promotions
final Int32List pieceCount;           // number of entries used
final Int32List squareIndex;          // for each square: its index in its pieceSquares list
```

- Max count per type: 10 is enough for 8 pawns→promotions + 2 original pieces. Use 10 for
  non-pawns, 8 for pawns, 1 for kings, but a uniform 10 is simpler.
- **Add:** `pieceSquares[k][pieceCount[k]] = sq; squareIndex[sq] = pieceCount[k]++`.
- **Remove:** swap-with-last. Move the last entry into the removed slot, update `squareIndex` of the
  moved piece, decrement the count.
- **Move:** replace the square in place (`pieceSquares[k][squareIndex[from]] = to;
  squareIndex[to] = squareIndex[from]`). Cheaper than remove + add.
- Note: after a swap-with-last remove and re-add during undo, the *order* within a list can change.
  That is fine for correctness, but **move generation order then changes**, so move order and
  therefore node counts can differ from the baseline. If you want identical node counts for
  verification, either sort before use, or compare perft (order-independent) instead.
  Perft must match exactly, and benchmark best moves should be the same or explainably different.

### Steps
1. **Add the structures** to `Board`, plus a private `_rebuildPieceLists()` called at the end of
   `Board.fromFEN`. Check whether other code constructs a `Board` or mutates `position` directly
   (`grep -rn "position\[" lib/engines/v11`). `inCheckAfterEnPassant` temporarily changes
   `position` and puts it back. The piece lists are not affected as long as the restore is exact,
   but don't call anything that reads the lists in between.
2. **Update `makeMove`** (`board.dart:43`). Everything that touches `position` gets a list op:
   - normal move: move mover `from → to`
   - capture: remove the captured piece from its list (before the mover lands)
   - en passant: remove the pawn on `enPassantCaptureSquare`
   - promotion: remove the pawn from the pawn list and add the new piece at `to`
   - castling: also move the rook
3. **Update `unMakeMove`** (`board.dart:181`) as the exact mirror. Be careful that `unMakeMove`
   already has an ordering trap around en passant (the `capturedPiece = 0` after restoring the
   pawn). Re-read it before editing.
4. **Add a debug validator** `assertListsMatchPosition()` that rebuilds from `position` and compares
   as sets. Call it from a test that plays random legal moves and unmakes them, including castling,
   en passant and promotions (use a few FENs that force each).
5. **Switch the consumers:**
   - `MoveGenerator.init()` / `findPieces()`: read from the board lists instead of scanning, and
     drop `friendlyPawnIndexes` etc. in favour of iterating `board.pieceSquares[...]` with
     `pieceCount`. Get king squares from the king list. This also lets you delete the
     `indexWhere` king search.
   - Keep `friendly*`/`opponent*` naming through small accessors, or loop with a local list ref.
6. **Allocation clean-up (while you're in `init()`):** `moves`, the `Set`s and the pin ray lists are
   allocated on each call. Reusing them (clear instead of new) is a separate, optional win. Note
   `generateLegalMoves` returns `moves`, which the caller loops over *while recursing*, so you can
   only reuse a list per ply, not one global list. A per-ply move list pool is the safe version.
   Treat this as its own measured step.

### Done when…
- [ ] Random make/unmake test passes with the validator on, over thousands of plies.
- [ ] Perft unchanged.
- [ ] Benchmark nps up; record in the Results log.

---

## Phase 5 — Incremental material, PST and phase

### Idea
Don't recompute the score from scratch. Update it as pieces move. After Phase 4 you also have piece
counts for free.

Keep on `Board`:
```dart
int mgScore;   // white minus black, PeSTO mg: PST + material
int egScore;   // white minus black, PeSTO eg
int phase;     // sum of knights/bishops 1, rooks 2, queens 4 (both sides)
```
(Piece counts per colour and type come from `pieceCount` in Phase 4. Bishop square colour counts
for the mop-up code need either two extra counters or a quick loop over the bishop list. The list
is at most a handful of entries, so looping it is fine and only happens in endgames.)

### Cost vs benefit (answering "will this be slow?")
Per move this adds a few integer adds and subtracts: `±pst[piece][sq]` and `±value` for the mover
(remove `from`, add `to`), plus the captured piece, plus extras for promotion, en passant and
castling. That is on the order of 4–10 operations per move. Compare that to the full evaluator: a
64-square loop with a switch and list writes on every Q-node. Q-search evaluates far more positions
than it makes moves, and the evaluation becomes O(1). Net result: clearly faster.

### Steps
1. **Flatten the PST data.** `PieceSquareTables` has one list per piece and phase. Build
   `mgTable[type]` and `egTable[type]` lookups (or one `Int32List` indexed
   `type * 64 + sq`) that **fold in material** (`mgPieceValues[type] + pst[sq]`), so one lookup
   per piece per side.
2. **Square orientation.** The evaluator uses `sq = color == white ? i : i ^ 56` and a sign. Do the
   same in the update helper: `_pieceScore(piece, sq)` returns the white-positive contribution.
   Kings have no material value (`type != king` check at `evaluator.dart:114`), but do have PST.
3. **Helpers** `_addPiece(piece, sq)`, `_removePiece(piece, sq)` that update `position`, the piece
   lists (Phase 4), mg/eg and phase together. Make `makeMove`/`unMakeMove` use only these, so
   there is a single place where state changes. That is also where it's easy to get bugs, so
   keep them tiny.
4. **Undo.** Store the previous `mgScore`, `egScore`, `phase` in `GameState` (like `zobristKey`)
   and restore them in `unMakeMove`. This is simpler and safer than reversing the arithmetic.
5. **Initialise** in `fromFEN` by scanning once.
6. **Rewrite `Evaluator.evaluate`:**
   - Read counts from `board.pieceCount`, scores from `board`.
   - Keep the draw check (`noHeavy && ...`), the mop-up branch and the tapered return unchanged,
     just fed from board counts instead of the local lists. The mop-up branch keeps using material
     only (`whiteMaterialScore - blackMaterialScore`): compute that from the counts and
     `pieceValues` in the rare branch where it is needed (bare king).
   - Delete the seven `List<int>` fields and the 64-square loop.
7. **Verification.** Add a debug check that, after random playouts, the incremental
   `mg/eg/phase` equals a from-scratch recompute, and that the new `evaluate` equals the **old**
   `evaluate` (keep a copy as `evaluateSlow` in a test file) for many positions. They must be
   identical integers.

### Gotchas
- Promotion changes phase and counts; en passant removes a pawn that is not on `move.to`; castling
  moves two pieces. These are the usual sources of drift.
- `phase` is capped with `min(calculatePhase(), 24)` in the evaluator. Keep that.
- The zobrist update in `makeMove` has existing quirks (for example, the castling rook XOR uses
  `position[rookTargetIndex]` after the rook has been moved). It's correct, but when refactoring
  into helpers make sure you don't change which values get hashed. Compare zobrist keys in the same
  playout test.

### Done when…
- [ ] Incremental scores equal from-scratch scores across random playouts.
- [ ] New `evaluate` equals old `evaluate` on a large set of positions.
- [ ] Benchmark best moves and node counts unchanged (pure speed-up), nps up.

---

## Optional follow-ups (not in scope)
- Reuse move lists per ply (see Phase 4 step 6) and avoid allocating `Set`s in the generator.
- Replace `hashHistory: HashMap` with a flat array of keys for repetition checks.
- Avoid allocating a `GameState` per `makeMove` (preallocated stack of states).
- Check extensions, SEE, late move reductions, null-move pruning.

---

## Results log

Fill in as you go. Same machine, same FEN set, same depth, release/AOT mode if possible.

| Step | Total nodes | Q-nodes | nps | Time to depth | firstMove/betaCutoffs | Notes |
|---|---|---|---|---|---|---|
| Baseline (v11 start, depth 7) | 10,637,144 | 6,379,260 | 691k | 15.4 s | 89.2% (390,401 / 437,785) | `tool/bench_v11.dart`, AOT. Perft 347,848 nodes in 82 ms (4.2M nps), PASS |
| Phase 1 delta pruning | | | | | | margin = |
| Phase 2 Q-search movegen | | | | | | |
| Phase 3b killers | | | | | | |
| Phase 3c history | | | | | | |
| Phase 3d attacked-square penalty | | | | | | |
| Phase 3e check bonus | | | | | | |
| Phase 4 piece lists | | | | | | |
| Phase 5 incremental eval | | | | | | |
