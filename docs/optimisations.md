Still reading — I've been through v12's search, eval and move generator, and now I'm checking your docs folder so I don't suggest things you've already planned.

I went through v12, the latest version: the search, eval, move ordering, transposition table (TT), the new bitboard board and move generator, and your `docs/` plans. Some of what's below is already in `docs/bitboard_plan.md`, and I've marked those. The rest is either new or a specific problem I found in the current code.

Your matches give each engine a fixed 100 ms per move, so two kinds of change make it stronger:

- **Speed:** more positions searched per second means deeper search in the same time.
- **Smarts:** not wasting time on bad moves, so the same time goes further.

---

# The simple list

**A. Finish making v12 fast**

1. Reuse move buffers instead of making a new list at every position _(already in `docs/move_buffers.md`)_
2. Stop the evaluator creating new lists every call
3. Incremental evaluation: keep the score up to date as moves are made
4. Magic bitboards _(already in `docs/magic_bitboards.md`)_
5. Small speed fixes in the move generator and search

**B. Search smarter**

6. Principal Variation Search (PVS)
7. Aspiration windows
8. Check extensions
9. Null move pruning
10. Late Move Reductions (LMR)
11. Reverse futility pruning
12. Futility pruning and late move pruning
13. Mate distance pruning and a max-ply guard

**C. Better move ordering**

14. Killer moves
15. History heuristic
16. Static Exchange Evaluation (SEE)

**D. Better transposition table**

17. Keep the TT move when a search "fails low"
18. A replacement scheme that keeps the valuable entries
19. Let the root and quiescence search use the TT

**E. Better evaluation**

20. Bishop pair, passed pawns, pawn structure
21. Mobility
22. King safety
23. Rook on open file, tempo
24. Texel tuning

**F. Testing**

25. SPRT, so you can tell whether each change actually helped
26. A fixed Zobrist seed, so benchmark runs are repeatable

---

# The detail

The Elo numbers are rough guesses for an engine at your level. Where they come from typical results, I say so. Measure each change on its own (see #25).

---

## A. Speed

### 1. Move buffers _(already planned)_

**Like you're 5:** Every time you think about a position, you go out and buy a brand-new notebook to write the moves in, then throw it away. Buy 128 notebooks once, one for each level of thinking, and reuse them.

**Implementation:** Your `docs/move_buffers.md` already covers this well. One more point: `_plyScores` already does this for scores, so give `moveBuf` the same `[ply]` indexing. Then `pickBest` swaps entries in two `Int32List`s instead of a `List<Move>`.

### 2. Stop the evaluator creating lists

**Like you're 5:** Each time you count the pieces, you build seven new counting boxes. Just empty the old ones.

**Where:** `search/evaluator.dart:57-63`. `pawns = [0, 0]` and the lines after it run on every `evaluate()` call, which is seven allocations per evaluation, and evaluations happen in nearly every quiescence node.

**Implementation:** With bitboards you don't need the loop over 64 squares at all:

```dart
final bb = board.pieceBB;
pawns[0]   = BitOps.popCount(bb[Piece.whitePawn]);
pawns[1]   = BitOps.popCount(bb[Piece.blackPawn]);
knights[0] = BitOps.popCount(bb[Piece.whiteKnight]);
// ...same for bishops, rooks, queens
lightBishops[0] = BitOps.popCount(bb[Piece.whiteBishop] & LIGHT_SQUARES);
darkBishops[0]  = BitOps.popCount(bb[Piece.whiteBishop] & DARK_SQUARES);
whiteKing = BitOps.lsb(bb[Piece.whiteKing]);
```

Make the lists `final Int32List pawns = Int32List(2);` and only write into them. I checked `LIGHT_SQUARES`: it matches your `(i ~/ 8 + i % 8) % 2 == 0` test.

### 3. Incremental evaluation (big speed gain)

**Like you're 5:** Instead of recounting every coin in your piggy bank each time, write down the total and add or subtract when a coin goes in or out.

**Implementation:** PeSTO is just "sum of table values", so it's ideal for this. `_put`, `_remove` and `_move` in `board.dart` already touch every piece change, so update the score there.

1. At startup, build combined tables that already include material, the colour flip and the sign:

```dart
// in Board (or a new core/eval_tables.dart, still within v12 so snapshot purity holds)
static final Int32List mgTable = Int32List(16 * 64);
static final Int32List egTable = Int32List(16 * 64);
static const phaseInc = [0, 0, 0, 1, 1, 2, 4]; // by type: none,K,P,N,B,R,Q

// for each piece code p and square sq:
//   white: sq' = sq,      sign = +1
//   black: sq' = sq ^ 56, sign = -1
//   mgTable[p*64+sq] = sign * (mgPieceValues[type] + pstMg[type][sq'])
```

(The PST imports live in `search/`. Either move the tables into `core/` or pass them in, whichever you like.)

2. Add `int mg = 0, eg = 0, phase = 0;` to `Board`. In `_put`: `mg += mgTable[piece*64+sq]; eg += egTable[...]; phase += phaseInc[piece & 7];`. In `_remove`, subtract. In `_move`, subtract `from` and add `to`.
3. You don't need to save or restore them in unmake, because unmake calls the same `_put`/`_remove`/`_move` in reverse.
4. `evaluate()` then becomes: `p = min(phase, 24); e = (mg*p + eg*(24-p)) ~/ 24`, plus the mop-up and insufficient-material checks from #2.

**Test:** For a few thousand random positions reached by random moves, assert that the incremental `mg`/`eg` equal a from-scratch calculation. This one change is what makes #11 and #12 cheap.

### 4. Magic bitboards _(already planned)_

**Like you're 5:** Instead of walking along each line to see where a rook stops, you look up the answer in a giant pre-made answer book.

Your doc covers it. One thing to watch: `_sliderMoves` takes `s.bishopAttacks` as a function tear-off, which stops Dart from inlining it. Write three separate loops, or pass an int "kind" and switch on it.

### 5. Small speed fixes

- **`move_generator.dart:86`:** `_pinRay.fillRange(0, 64, 0)` runs on every call. `_pinRay` is only read for squares in `pinned`, and those are always written first, so delete the clear.
- **`searcher.dart:166`:** The 50-move check runs _after_ `moveGenerator.generate`. Move it before the TT probe, keeping the mate check: `if (board.halfMove >= 100 && !board.isInCheck()) return drawScore;`. This matches what your comment intends in nearly all cases.
- **In check, computed twice:** `quiescenceSearch` calls `board.isInCheck()`, then `generate` works out the checkers again. Have `generate` return or store `inCheck` (you already set `lastCheckers`) and read it afterwards. You'll want `inCheck` at the top of `search()` for #8–12 anyway, so compute it once per node.
- **Root ordering:** `orderedMoves.where(...)` builds a new list every iteration. That's cheap, but #7 replaces it anyway.
- **Measure `Uint64List` reads:** Values with bit 63 set don't fit Dart's small-int format and can get "boxed" (stored as heap objects). In AOT, local variables are usually unboxed, but profile `makeMove` with DevTools. If it shows up, plain `Int64List` behaves the same for bitboards.

---

## B. Search

At the moment `search()` is plain alpha-beta with a TT. Every pruning idea below is missing, and they are where most Elo comes from.

**Before you start:** Add `bool inCheck = board.isInCheck();` and `bool pvNode = beta - alpha > 1;` near the top of `search()`. Most of the techniques below depend on them.

### 6. Principal Variation Search (PVS)

**Like you're 5:** Once you've found a good move, you don't need to know exactly how good the others are, only "is it better, yes or no?". Yes/no questions are much quicker to answer. Only if the answer is "yes" do you go back and measure properly.

**Implementation** in the move loop of `search()`:

```dart
int eval;
if (i == 0) {
  eval = -search(depth - 1, ply + 1, -beta, -alpha);
} else {
  // null window: "can this beat alpha?"
  eval = -search(depth - 1, ply + 1, -alpha - 1, -alpha);
  if (eval > alpha && eval < beta) {
    eval = -search(depth - 1, ply + 1, -beta, -alpha); // re-search properly
  }
}
```

This works with your fail-hard returns as they are. You'll mostly see it pay off once ordering (#14–15) is good. Typical gain: +20–40.

### 7. Aspiration windows

**Like you're 5:** Last time you guessed the answer was about 30. This time, ask "is it between 5 and 55?". That's quicker to check than "is it anything at all?". If you're wrong, ask again with a wider range.

**Implementation:** First, simplify the root. Let `search()` handle ply 0 itself and record the best move:

```dart
if (ply == 0 && eval > alpha) rootBestMove = move; // inside the eval > alpha branch
```

Then the TT move does the job of putting the previous best first, and you can delete the separate root loop in `getBestMove`. Iterative deepening becomes:

```dart
int prev = 0;
for (int d = 1; d <= maxDepth; d++) {
  int window = 40;
  int alpha = d >= 4 ? prev - window : -INF;
  int beta  = d >= 4 ? prev + window :  INF;
  while (true) {
    final score = search(d, 0, alpha, beta);
    if (aborted) break;
    if (score <= alpha)      { alpha = max(-INF, alpha - window); window *= 2; }
    else if (score >= beta)  { beta  = min( INF, beta  + window); window *= 2; }
    else { prev = score; break; }
    if (window > 1000) { alpha = -INF; beta = INF; }
  }
  // commit rootBestMove/prev only if !aborted (or if the partial search found something)
}
```

Watch out: with fail-hard search, a fail-low at the root can leave `rootBestMove` unset or junk. Only trust it from a search that finished inside its window, or from the previous iteration. Typical gain: +10–20.

### 8. Check extensions

**Like you're 5:** When someone says "check!", things are getting exciting, so look one move further than you'd planned.

**Implementation**, at the top of `search()` before the `depth == 0` test:

```dart
if (inCheck) depth++;
```

Positions in check have few legal moves, so this is cheap, and it fixes a lot of "didn't see the mate" horizon problems. Your quiescence check limit `qCheckDepthLimit = 1` matters less after this.

Add the max-ply guard from #13 at the same time so a long chain of checks can't run away. Typical gain: +20–30.

### 9. Null move pruning (biggest single gain)

**Like you're 5:** Imagine you skip your turn completely and let your opponent move twice. If you're _still_ winning, you were obviously doing great, so stop thinking about this position.

**Implementation.** First write `makeNullMove` (your plan lists it as still to do) in `board.dart`:

```dart
void makeNullMove() {
  undoEp[plyCount] = epSquare;
  undoHalfMove[plyCount] = halfMove;
  undoCastling[plyCount] = castling;
  keyStack[plyCount] = zobristKey;
  zobristKey ^= Zobrist.enPassantSquares[epSquare + 1];
  epSquare = -1;               // enPassantSquares[0] is 0, so nothing to XOR back in
  zobristKey ^= Zobrist.sideToMove;
  whiteToPlay = !whiteToPlay;
  plyCount++;
  halfMove = 0;                // a repetition can't span a null move
}

void unMakeNullMove() {
  plyCount--;
  epSquare = undoEp[plyCount];
  halfMove = undoHalfMove[plyCount];
  zobristKey = keyStack[plyCount];
  whiteToPlay = !whiteToPlay;
}
```

Then in `search()`, after the TT probe and before generating moves:

```dart
if (!pvNode && !inCheck && allowNull && depth >= 3 && ply > 0 &&
    _hasNonPawnMaterial(board) && !isMate(beta)) {
  final r = 2 + depth ~/ 4;    // or simply 2 for depth < 6, 3 otherwise
  board.makeNullMove();
  final score = -search(depth - 1 - r, ply + 1, -beta, -beta + 1, allowNull: false);
  board.unMakeNullMove();
  if (aborted) return 0;
  if (score >= beta) return beta;   // never return a mate score from here
}
```

- `_hasNonPawnMaterial` checks `pieceBB[knight|bishop|rook|queen of side to move] != 0`. This protects against zugzwang, where moving at all makes things worse, which happens mostly in king-and-pawn endings.
- `allowNull: false` stops two null moves in a row.
- Make sure the repetition check doesn't count the null move: `halfMove = 0` handles that.

Typical gain: +60–100.

### 10. Late Move Reductions (LMR)

**Like you're 5:** Your best ideas are usually at the top of your list. For ideas near the bottom, take a quick, shallow look. Only if one surprises you do you look at it properly.

**Implementation**, combined with PVS:

```dart
// precompute once: Int8List lmr = 64*64, lmr[d*64+i] = (0.75 + log(d)*log(i)/2.25).floor()
board.makeMove(move);
final givesCheck = board.isInCheck();
int eval;
if (i == 0) {
  eval = -search(depth - 1, ply + 1, -beta, -alpha);
} else {
  int r = 0;
  if (depth >= 3 && i >= 3 && isQuiet && !inCheck && !givesCheck && !isKiller) {
    r = lmr[min(depth, 63) * 64 + min(i, 63)];
    if (pvNode) r--;
    r = r.clamp(0, depth - 2);
  }
  eval = -search(depth - 1 - r, ply + 1, -alpha - 1, -alpha);
  if (eval > alpha && r > 0) eval = -search(depth - 1, ply + 1, -alpha - 1, -alpha);
  if (eval > alpha && eval < beta) eval = -search(depth - 1, ply + 1, -beta, -alpha);
}
board.unMakeMove(move);
```

`isQuiet` means not a capture and not a promotion: `board.squares[move.to] == 0 && !move.isPromotion && !move.enPassantCapture`, checked _before_ `makeMove`.

LMR only works if ordering is good, so do #14–15 first. Typical gain: +50–100.

### 11. Reverse futility pruning (static null move)

**Like you're 5:** If you're already way ahead, so far ahead that even a bit of bad luck won't matter, don't bother thinking hard.

**Implementation**, before move generation:

```dart
if (!pvNode && !inCheck && depth <= 6 && !isMate(beta)) {
  final staticEval = evaluator.evaluate(board);   // cheap after #3
  if (staticEval - 90 * depth >= beta) return staticEval; // or `return beta` to stay fail-hard
}
```

Typical gain: +20–40.

### 12. Futility pruning and late move pruning

**Like you're 5:**

- _Futility:_ You're losing badly and only one move from the end. A quiet little move won't rescue you, so only look at captures.
- _Late move pruning:_ At the end of a long, shallow list of quiet moves, just skip the rest.

**Implementation**, in the move loop at non-PV nodes that are not in check:

```dart
const futilityMargin = [0, 150, 300, 450];
final bool canFutility = !pvNode && !inCheck && depth <= 3 &&
                          staticEval + futilityMargin[depth] <= alpha;
int quietsSeen = 0;
...
if (isQuiet) quietsSeen++;
if (i > 0 && isQuiet && !isKiller) {
  if (canFutility) continue;                                // futility pruning
  if (!pvNode && !inCheck && depth <= 3 && quietsSeen > 3 + depth * depth) continue; // late move pruning
}
```

Skip futility for moves that give check. That needs `makeMove` first, so either test it after `makeMove` and unmake on skip, or accept the small loss. Typical gain: +20–40 combined.

### 13. Mate distance pruning and a max-ply guard

**Like you're 5:** If you've already found a way to win in 3 moves, don't spend time on wins that take 10.

```dart
if (ply >= 120) return evaluator.evaluate(board);     // guard; _plyScores is 256
if (ply > 0) {
  alpha = max(alpha, mateScore + ply);
  beta  = min(beta, -mateScore - ply - 1);
  if (alpha >= beta) return alpha;
}
```

Small Elo gain, but it makes mates come out faster and cleaner.

---

## C. Move ordering

At the moment, every quiet move scores 0 in `_calculateMoveScore`, so they're tried in whatever order the generator produced them. Better ordering makes every alpha-beta cutoff happen sooner, and LMR depends on it.

**Before you start:** Re-space the scores so the categories don't overlap.

| Category                                 | Score                             |
| ---------------------------------------- | --------------------------------- |
| TT move                                  | 1,000,000                         |
| Winning or equal captures and promotions | 100,000 + MVV-LVA                 |
| Killer 1                                 | 90,000                            |
| Killer 2                                 | 80,000                            |
| Quiet moves                              | history score (kept below 80,000) |
| Losing captures (SEE < 0, see #16)       | -100,000 + MVV-LVA                |

MVV-LVA means "most valuable victim, least valuable attacker": capture the biggest piece with the smallest one first.

Your `scoreMoves` will need extra parameters: `ply` and whose turn it is.

Also note that en passant currently scores as a quiet move, because `squares[move.to]` is empty. Treat `move.enPassantCapture` as a pawn-takes-pawn capture.

### 14. Killer moves

**Like you're 5:** "Last time I was in a situation like this, moving my knight there was brilliant. Let me try that first again."

```dart
final Int32List killers = Int32List(256 * 2);  // [ply*2 + 0/1]

// on beta cutoff in search(), if the move is quiet:
if (isQuiet && killers[ply * 2] != move.value) {
  killers[ply * 2 + 1] = killers[ply * 2];
  killers[ply * 2] = move.value;
}
```

Clear the killers for `ply + 2` when entering a node, or clear them all at the start of each `getBestMove`. Typical gain: +30–50.

### 15. History heuristic

**Like you're 5:** Keep a scoreboard: "moving a piece from this square to that square has caused lots of cutoffs." Moves with high scores get tried first.

```dart
final Int32List history = Int32List(2 * 64 * 64); // [colour*4096 + from*64 + to]

// on beta cutoff by a quiet move:
final idx = us * 4096 + move.from * 64 + move.to;
history[idx] += depth * depth;
// optional "malus": subtract depth*depth from each quiet move tried before it in this node
if (history[idx] > 70000) { for (i...) history[i] >>= 1; } // keep under killer scores
```

In `scoreMoves`, use `history[...]` as the score for quiet moves. At the start of each `getBestMove`, halve every entry rather than zeroing it, so useful knowledge carries over between moves. Typical gain: +20–40.

### 16. SEE (Static Exchange Evaluation)

**Like you're 5:** Before grabbing a pawn with your queen, count who's guarding it. If they'll take your queen back, it's a bad trade.

**Implementation** (the "swap list" algorithm). Your `attackersOfSquare(sq, occupied, attacker)` already takes an occupancy, which is exactly what x-rays need. An x-ray is a piece hidden behind another one on the same line, which joins in once the front piece is gone.

```dart
int see(Board b, Move m) {
  final to = m.to; int from = m.from;
  final gain = Int32List(32); int d = 0;
  int occ = b.colourBB[0] | b.colourBB[1];
  int side = b.whiteToPlay ? 0 : 1;
  gain[0] = value[Piece.type(b.squares[to])];
  int pieceOnSq = Piece.type(b.squares[from]);
  int attackers = b.attackersOfSquare(to, occ, 0) | b.attackersOfSquare(to, occ, 1);
  while (true) {
    d++;
    gain[d] = value[pieceOnSq] - gain[d - 1];
    if (max(-gain[d - 1], gain[d]) < 0) break;
    occ ^= 1 << from;  attackers &= occ;
    attackers |= (rookAttacks(to, occ) & (allRooks | allQueens) |
                  bishopAttacks(to, occ) & (allBishops | allQueens)) & occ; // x-rays
    side ^= 1;
    // least valuable attacker of `side`: loop pawn, knight, bishop, rook, queen, king
    final mine = attackers & b.colourBB[side];
    if (mine == 0) break;
    (from, pieceOnSq) = leastValuable(b, mine, side);
  }
  while (--d > 0) gain[d - 1] = -max(-gain[d - 1], gain[d]);
  return gain[0];
}
```

Use it in two places:

1. **Quiescence:** `if (!inCheck && see(move) < 0) continue;`. This cuts the number of quiescence nodes a lot.
2. **Ordering:** put losing captures after killers.

En passant and promotions are edge cases; just treat their SEE as ≥ 0. Typical gain: +20–40.

---

## D. Transposition table

### 17. Keep the TT move on fail-low

**Like you're 5:** You had a note saying "the best move here was e4". You looked again, nothing beat your target, and you replaced the note with "no idea". Keep the old note.

**Where:** `searcher.dart:194`. When no move raises alpha, it stores `bestMoveHere ?? Move.invalid`, which wipes out the good move from the previous iteration.

**Fix**, in `store()`:

```dart
if (move.isNoMove && _keys[i] == key) move = Move.raw(_moves[i]); // keep old move
```

### 18. Replacement scheme

**Like you're 5:** Your notebook is full. Don't rub out a note that took an hour to work out to make room for one that took a second.

The TT currently always overwrites. Add an age so old entries from earlier moves can be replaced:

```dart
final Uint8List _ages;     // new
int age = 0;               // bump once per getBestMove

void store(...) {
  final i = index(key);
  final replace = _keys[i] != key ? (_ages[i] != age || depth >= _depths[i]) : true;
  if (!replace) return;
  ...
  _ages[i] = age;
}
```

A better option is two slots per index: one "depth-preferred" and one "always replace". Probe both. For more speed, pack score, move, depth and flag into one `Int64List` word next to the key, so a probe is two memory reads instead of five.

### 19. Use the TT more

- **Root:** Covered by #7 once `search()` handles ply 0.
- **Quiescence:** Probe at the top, treating a stored depth ≥ 0 as usable, and use `ttMove` for ordering.
- **Don't cut on TT at PV nodes:** Only do the TT cutoff when `!pvNode`, or when the flag is exact. That keeps PVs cleaner and makes repetition-draw scores less likely to leak into the wrong place.

---

## E. Evaluation

Right now the evaluation is just PeSTO tables plus mop-up. With bitboards, each of these extra terms is a few AND and popcount operations. Use separate mg and eg values for each term, the same way the PST is tapered.

**Before you start:** Precompute these masks in `AttackTables`:

- `fileMask[8]`
- `adjacentFiles[8]`
- `passedMask[2*64]`: the squares in front of a pawn, on its own file and both neighbours, towards promotion
- `kingZone[64]`: `kingAttacks[sq] | 1 << sq`

### 20. Pawns and bishop pair

**Like you're 5:**

- Two bishops work great as a team.
- A pawn with nobody left to stop it is dangerous.
- A pawn with no friends next to it is weak.
- Two pawns stacked on one file get in each other's way.

| Term          | How to detect it                          | Starting values                                                                          |
| ------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------- |
| Bishop pair   | `popCount(bishops[c]) >= 2`               | +30 mg / +50 eg                                                                          |
| Passed pawn   | `(theirPawns & passedMask[c*64+sq]) == 0` | eg bonus by rank from own side: `[0, 10, 15, 25, 45, 75, 120, 0]`; about half that in mg |
| Isolated pawn | `(ourPawns & adjacentFiles[file]) == 0`   | −10 mg / −15 eg                                                                          |
| Doubled pawns | `popCount(ourPawns & fileMask[f]) > 1`    | −10 mg / −20 eg per extra pawn                                                           |

Pawn structure changes rarely, so you can cache it later: a small pawn hash table keyed by a pawn-only Zobrist key.

### 21. Mobility

**Like you're 5:** A piece that can go to lots of places is more useful than one stuck in a corner.

```dart
final safe = ~ourBB & ~theirPawnAttacks;   // theirPawnAttacks from shifting their pawn BB
knightMob = popCount(knightAttacks[sq] & safe);         // weight ~4 mg / 4 eg, centred on 4
bishopMob = popCount(bishopAttacks(sq, occ) & safe);    // ~5 / 5, centred on 6
rookMob   = popCount(rookAttacks(sq, occ) & safe);      // ~2 / 4, centred on 7
queenMob  = popCount(queenAttacks(sq, occ) & safe);     // ~1 / 2, centred on 13
```

This needs magic bitboards (#4) to be cheap. Typical gain: +30–50.

### 22. King safety

**Like you're 5:** Keep pawns in front of your king like a wall, and worry when enemy pieces gather around it.

- **Pawn shield:** Count our pawns on the 2 squares in front of the king, on the king's file and both neighbours. Add a mg bonus of about +10 each.
- **Attack count:** While computing mobility, count the enemy pieces whose attacks touch `kingZone[ourKing]`, weighted N/B = 2, R = 3, Q = 5. Apply a mg penalty from a table, e.g. `[0, 0, 5, 15, 30, 50, 75, 100, ...]`.

### 23. Rook on open file and tempo

- **Rook files:** No pawns at all on the rook's file: +25 mg. Only enemy pawns on it: +12.
- **Tempo:** Add +10 to whoever is to move, i.e. after the side-to-move flip. This takes a few seconds to add and helps a little.

### 24. Texel tuning

**Like you're 5:** Show the engine thousands of positions where you know who ended up winning. Nudge every number in the evaluation, little by little, until its guesses match the real results best.

**Implementation:**

1. Collect about 1M quiet positions, with the result of each game (1, ½ or 0). Your match runner already writes PGNs, so you can mine those. Use positions where qsearch's score equals the static eval.
2. Error = mean over positions of `(result − sigmoid(K * eval))²`, where `sigmoid(x) = 1 / (1 + 10^(−x/400))`. First fit K on its own.
3. Put every eval parameter in one `List<int>`. Repeatedly try ±1 on each parameter and keep the change if the error drops; stop when nothing improves. This is plain local search, and gradient descent is faster if you want it.

Run it as a `tool/` script, never inside the app. Typical gain: +50–100 once you have the terms above.

---

## F. Testing

### 25. SPRT

**Like you're 5:** Don't play a fixed 1000 games. Keep playing until you're _sure_ the new version is better or worse, then stop. Clear wins and clear losses stop early.

**Implementation:** You'd add this to `match_stats.dart`. After each game pair, compute the log-likelihood ratio (LLR) for H0 = 0 Elo against H1 = +5 Elo. The pentanomial or trinomial formulas are on the Chess Programming Wiki, or copy the approach from fastchess. Stop when LLR ≥ 2.94 (pass) or ≤ −2.94 (fail); those bounds give 5% error rates.

Test **one** change at a time against the previous version. Some of the ideas above lose Elo when their constants are wrong, and SPRT is how you'd find out.

### 26. Fixed Zobrist seed

`Zobrist._random = Random()` is unseeded, so every run gets different keys. That makes TT collisions, and in rare cases node counts, vary from run to run, which matters for your "node counts must not change" benchmark rule. Use `Random(12345)` so runs are repeatable.

---

## Suggested order

1. **Finish v12:** #1, #2, #3, #5, then #4. Pure speed, same behaviour, so the match measures only the speed gain. This is what your plan intends.
2. **v13:** #14, #15 (ordering), then #17, #18, then #6, #8, #9, #13.
3. **v14:** #10, #11, #12, #16, #7.
4. **v15:** #20–23, then #24.

Run SPRT (#25) on each step.

I can also save this as `docs/optimisations.md` alongside your other plan docs if that's useful.
