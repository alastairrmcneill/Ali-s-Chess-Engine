# V12: bitboard board and move generator (detailed implementation plan)

## Status

Built in `lib/engines/v12/`, which started as a copy of v11 (v11 already has move packing and ordering improvements). The baseline for every comparison is **v11**.

| Milestone | State |
| --- | --- |
| M0 baseline bench | `tool/bench_v11.dart` exists; record v11 numbers if not done |
| M1 bit utilities + attack tables | done |
| M2 board, make/unmake, Zobrist | done: bitboards, `castling` / `epSquare`, undo arrays, `keyStack`, `isRepetition`. Old `hashHistory` / `GameState` / `fiftyMoveRule` removed. `makeNullMove` not yet written (needed later) |
| M3 sliders | done, tested (`test/engines/v12/sliders_test.dart`) |
| M4 move generator | next. `Board.isInCheck()` does not exist yet (step 2) |
| M5-M8 | not started |

Note: `Move` is an `extension type const Move.raw(int)` in `core/move.dart`, not the Chess Programming Wiki layout the original plan described. M2 below documents the real encoding.

## Context

V11 (`lib/engines/v11`) spends most of its time on board bookkeeping rather than searching:

- It tracks attack maps and pin/check rays in `Set<int>`s.
- It rescans all 64 squares on every `generateLegalMoves`.
- It allocates a heap `Move` object for every move and a `GameState` per `makeMove`.
- It updates a `HashMap` for repetitions on every make/unmake.

Matches run at 100 ms/move, so nodes per second (NPS) turns almost directly into depth, and depth into Elo. The goal of V12 is to **replace the board representation and move generator with bitboards and keep the V11 search and eval behaviour as close to identical as possible**. Then the V12-vs-V11 match measures the speed gain alone. Search improvements (null move, killers, PVS, LMR and so on) come afterwards, as V13+, on top of the new API.

Targets, measured in AOT with `dart compile exe`:

- Perft speed at least 5× V11.
- Search NPS at least 3× V11.
- All perft, mate and new oracle tests green.
- Expected about +150–300 Elo vs V11 at 100 ms.

### Constraints found in the repo

- **Snapshot purity** (`test/engines/snapshot_purity_test.dart`): files under `lib/engines/v12/` may import only `dart:*`, `package:ace/engines/v12/...`, `package:ace/chess_core/notation/...` and `package:ace/engines/engine_interface.dart`. All cross-version comparison code must live in `test/`.
- **Registry-driven tests**: `perft_all_versions_test.dart` and `mate_all_versions_test.dart` iterate `EngineRegistry.allIds`. Registering `v12` brings it under perft and mate testing automatically.
- **Square indexing**: `FenPosition`, `UciMove`, `BoardHelper` and the PSTs all use **index 0 = a8, 63 = h1** (rank 8 first). **Keep this mapping**, with bit _i_ = square _i_. That means:
  - "North" (towards rank 8) is index −8, i.e. `>>> 8`.
  - "South" is `<< 8`.
  - East (file+1) is `<< 1`, masked with `~FILE_A`.
  - West is `>>> 1`, masked with `~FILE_H`.
- **Piece codes**: `FenPosition.position` uses V11's codes (type 1–6, white = 0, black = 8; max code 14). Keep `piece.dart` identical so the FEN parser and PSTs work unchanged.
- **Platform**: Dart native `int` is 64-bit two's-complement, and multiplication and `<<` wrap, which is what bitboards and magics need. On **web**, `int` is a JS double and `Uint64List` throws. Engines already run via `Isolate.spawn` (`lib/services/engine_worker.dart`), which web doesn't support, so web is out of scope. Note it in the README.

---

## File layout (new folder `lib/engines/v12/`)

| File                       | Source                               | Purpose                                                                                                                                                    |
| -------------------------- | ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `core/piece.dart`          | copy of v11                           | piece codes, unchanged                                                                                                                                     |
| `core/bitboard.dart`       | new                                  | constants (files, ranks, light squares), `BitOps` (popcount, lsb, msb, popLsb), square helpers, debug `toAscii()`                                          |
| `core/attack_tables.dart`  | new, replaces `precompute_data.dart` | knight/king/pawn attack `Uint64List`s, rays per direction, `between` and `line` tables (flat `Uint64List(4096)`), castling masks                           |
| `core/sliders.dart`        | new                                  | `rookAttacks(sq, occ)` / `bishopAttacks` / `queenAttacks`. Milestone 3 uses the classical ray approach; milestone 7 switches to magics behind the same API |
| `core/magic_numbers.dart`  | generated (M7)                       | const magic numbers and shifts for this square mapping                                                                                                     |
| `core/move.dart`           | done                                 | `extension type Move(int)`: from, to, flag packed in 16 bits (no heap objects)                                                                             |
| `core/zobrist.dart`        | adapted from v11                      | flattened `Int64List` tables, same random structure                                                                                                        |
| `core/board.dart`          | rewritten                            | bitboards + mailbox, make/unmake, null move, repetition stack                                                                                              |
| `core/bitboard_move_generator.dart` | new (M4)                    | legal generation, then (M5) into a caller-supplied `Int32List` buffer. Replaces the old `core/move_generator.dart`, which stays as the test oracle until M5 |
| `search/*.dart`            | copied from v11, ported to int moves  | `searcher`, `move_ordering`, `transposition_table`, `evaluator`, `piece_square_tables`, `opening_book(_data)`                                              |
| `v12_engine.dart`          | adapted from `v11_engine.dart`        | `ChessEngine` wrapper                                                                                                                                      |

Outside the folder:

- `lib/engines/engine_registry.dart`: `'v12'` is already registered.
- `README.md`: add the v12 line.
- `test/engines/v12/` (existing: `bitboard_test.dart`, `sliders_test.dart`; M4 adds `bitboard_move_generator_test.dart`)
- `tool/bench.dart` (generalise `bench_v11.dart`)
- `tool/generate_magics.dart`

---

## Milestone 0: baseline benchmark (before any V12 code)

`tool/bench_v11.dart` exists today; generalise it into one tool that takes an engine id. It imports only the `lib/engines/...` files, with no Flutter imports. It takes an engine id and runs:

- `perft` on startpos depth 5, Kiwipete depth 4 and Position 3 depth 5. It reports nodes, ms and Mnps.
- A fixed-depth search on about 10 middlegame/endgame FENs (depth 6, or depth 5 if slow). It reports nodes, ms, NPS, best move and eval from `EngineMoveResult`.

Run it AOT: `dart compile exe tool/bench.dart -o build/bench && build/bench v11`. JIT numbers are misleading for this kind of code. Record the V11 numbers in the PR description.

## Milestone 1: bit utilities and attack tables

**`core/bitboard.dart`**

```dart
const int FILE_A = 0x0101010101010101;      // a8,a7,...,a1 (indexes 0,8,...,56)
const int FILE_H = FILE_A << 7;
const int RANK_8 = 0xFF;                     // indexes 0-7
const int RANK_1 = 0xFF << 56;
const int RANK_2 = 0xFF << 48, RANK_3 = 0xFF << 40, RANK_6 = 0xFF << 16, RANK_7 = 0xFF << 8;
const int LIGHT_SQUARES = ...;               // squares where (rank+file) is even in this mapping (a8 is light)
```

`BitOps` holds static, `@pragma('vm:prefer-inline')` functions:

- **`popCount(b)`**: SWAR using `>>>`, with the final `(x * 0x0101010101010101) >>> 56`.
- **`lsb(b)`**: De Bruijn, `_index64[((b & -b) * 0x03f79d71b4cb0a89) >>> 58]`. It relies on the wrapping multiply.
- **`msb(b)`**: fold the high bits down (`b |= b >>> 1 ... >>> 32`), then De Bruijn. Only the classical sliders need it.
- **Pop-lsb iteration idiom**: `while (b != 0) { final sq = lsb(b); b &= b - 1; ... }`.
- **Gotcha: always use `>>>` (logical shift), never `>>`.** Bitboards with bit 63 set are negative ints, and `>>` would smear the sign bit.
- **Gotcha: hex literals above 2^63** (for example in magics) are legal on native but read as negative. Write the all-ones mask as `-1`.

**`core/attack_tables.dart`** builds everything once, on first use, in static finals:

- **`knightAttacks`, `kingAttacks`**: `Uint64List(64)`.
- **`pawnAttacks`**: `Uint64List(128)`, indexed `colour*64 + sq`.
  - White pawn on `sq` attacks `sq-9` (file−1) and `sq-7` (file+1).
  - Black attacks `sq+7` (file−1) and `sq+9` (file+1).
  - Include a file guard on each.
- **`rays`**: `Uint64List(8*64)`, using the same direction order as V11 (`N,E,S,W,NE,SE,SW,NW` = −8, +1, +8, −1, −7, +9, +7, −9).
- **`between`**: `Uint64List(64*64)`. Squares strictly between `a` and `b` when they're aligned, else 0.
- **`line`**: `Uint64List(64*64)`. The segment from `a` to `b`, both endpoints included, when aligned, else 0. It is **not** edge to edge, so don't use it to restrict pinned pieces (see M4 step 5).
- **`castleMask`**: `Int32List(64)`, starting at 15. Clear bits as follows:
  - `[56] &= ~4` (a1 → WQ)
  - `[63] &= ~8` (h1 → WK)
  - `[60] &= ~12` (e1)
  - `[0] &= ~1` (a8 → BQ)
  - `[7] &= ~2` (h8 → BK)
  - `[4] &= ~3` (e8)

  The bit order is the same as V11's `castlingRightsAsInt` (8 = WK, 4 = WQ, 2 = BK, 1 = BQ), so the Zobrist castling table indexes the same way.

Use flat typed lists everywhere (`table[a*64+b]`). V11's `List<List<int>>` costs two bounds-checked indirections per lookup.

## Milestone 2: board representation, make/unmake, Zobrist

**`core/move.dart`** (done) is `extension type const Move.raw(int value)`, a 16-bit packed int:

```
bits 0-5  from   bits 6-11  to   bits 12-15 flag
flag: 0 quiet or capture, 1 en passant, 2 castling, 3 double pawn push, 4 promo Q, 5 promo N, 6 promo R, 7 promo B
```

- Captures are **not** flagged: a capture is "target square is occupied" (or flag 1). Promotions with and without capture share flags 4 to 7.
- Constructors: `Move.encode(from, to, [flag])` (fast, for the generator) and the named-argument `Move(...)` (convenience). Getters: `from`, `to`, `flag`, `enPassantCapture`, `castling`, `pawnTwoForward`, `isPromotion`, `promotion` (1 Q, 2 N, 3 R, 4 B), `promotingPiece()`, `uci`.
- `Move.invalid` is `Move.raw(0)` (a8a8, never legal), the "no move" sentinel. Because `Move` is an extension type over `int`, a `Move` stores in an `Int32List` as `move.value` with no boxing, and the TT can hold it directly.

**`core/board.dart`** fields, all plain typed data with no `late`:

```dart
final Uint64List pieceBB = Uint64List(16);   // indexed by piece code (e.g. Piece.whiteKnight)
final Uint64List colourBB = Uint64List(2);   // 0 white, 1 black
final Uint8List squares = Uint8List(64);     // mailbox, kept in sync for O(1) piece-on-square
bool whiteToPlay; int castling; int epSquare /* -1 none */; int halfMove; int zobristKey;
int plyCount;                                // game ply for repetition stack indexing
// Undo stack, preallocated (MAX_GAME_PLY = 2048: 300-move game + search depth + margin)
final Int64List keyStack; final Int32List undoCaptured, undoCastling, undoEp, undoHalfMove;
```

- `Board.fromFEN` uses `FenPosition.parse`. It fills `squares`, `pieceBB` and `colourBB` through `_put`, sets `castling`, `epSquare` and `halfMove`, and computes the key. There is no `occupied` field: use `colourBB[0] | colourBB[1]`.
- Private inline helpers:
  - `_put(piece, sq)`: sets the bit in `pieceBB[piece]` and `colourBB`, sets `squares`, and XORs `zobrist[piece*64+sq]`.
  - `_remove(piece, sq)`: the reverse.
  - `_move(piece, from, to)`: one XOR mask `(1<<from)|(1<<to)` on each bitboard.
- **`makeMove(Move m)`**:
  1. Push `captured`, `castling`, `ep` and `halfmove`. Push the key onto `keyStack`.
  2. Read `piece = squares[from]` and `captured = squares[to]`. For en passant the captured pawn is on `to ± 8`.
  3. Remove the captured piece if there is one, then move the piece. On promotion, remove the pawn and put the promoted piece.
  4. Castling: also move the rook (h1→f1, a1→d1, h8→f8, a8→d8 by flag and colour).
  5. Ep: XOR out the old ep key, then set `ep = from ± 8` on a double push, else −1. XOR in the new key. Keep **V11's hashing semantics**: hash the ep square whenever there's a double push, so V11 and V12 keys behave alike.
  6. Castling rights: `castling &= castleMask[from] & castleMask[to]`. If they changed, XOR out the old Zobrist castling key and XOR in the new one.
  7. `halfmove = (pawn move || capture) ? 0 : halfmove + 1`. Flip the side to move and XOR `sideToMove`. Increment `plyCount`.
- **`unMakeMove(Move m)`** is the mirror image. Restore scalars from the stacks and **restore `zobristKey` from `keyStack`** rather than un-XORing.
- **`makeNullMove()` / `unMakeNullMove()`** (not written yet): flip the side, clear ep (with its key), and push the stacks. Unused in V12 but needed for null-move pruning in V13.
- **`isRepetition()`** replaces the `HashMap`. It scans `keyStack` from `plyCount-2` down to `plyCount-halfmove`, step −2, and returns true on the first match.
  - V11 rule: "seen ≥ 2 times including the current position, at ply > 0", which means one earlier occurrence. That's equivalent to "any earlier match", because positions before an irreversible move can't recur.
  - The search calls `board.isRepetition()` in place of `hashHistory[...] >= 2`.
- **`kingSquare(colour)`**: `lsb(pieceBB[Piece.king | colourCode])`.

**`core/zobrist.dart`**: same generation as V11, flattened:

- `Int64List pieces = (15*64)`
- `castling[16]`
- `ep[65]`
- `side`

Keep `ensureInitialised()` and the "statics per isolate" note. `Zobrist.getZobristForBoard(board)` is the from-scratch key used by `fromFEN` and the tests.

## Milestone 3: slider attacks, classical approach first

Use the ray tables and bitscans in `sliders.dart`. For each direction: `attacks |= rays[d][sq]`, then `blockers = rays[d][sq] & occ`, and if `blockers != 0` remove what's behind the first blocker.

- The first blocker is `lsb(blockers)` for directions that increase the index (E, S, SE, SW) and `msb(blockers)` for decreasing ones (N, W, NE, NW).
- Remove behind it with `attacks &= ~rays[d][firstBlocker]`.

This is simple, obviously correct, and a good oracle for the magic version in M7.

## Milestone 4: legal move generator

**Approach: new file, built in steps, checked against the old generator after every step.** Do not edit `move_generator.dart` in place. It builds attack maps and ray sets for the whole position and then filters. The new design works from checkers, pins and a check mask, so the two share almost no structure. The old generator stays untouched as the oracle until M5 swaps callers over.

**File:** `lib/engines/v12/core/bitboard_move_generator.dart`, class `BitboardMoveGenerator`.

**API: deliberately not a straight swap for the old generator.**

```dart
List<Move> generateLegalMoves(Board board, {bool capturesOnly = false});
```

M5 changes the output to an `Int32List` buffer (`int generate(Board b, Int32List out, {bool capturesOnly = false})`). Keep `List<Move>` for now so the oracle test can compare directly.

Differences from the old generator, all on purpose:

- **No `inCheck` / `inDoubleCheck` state on the generator.** Nothing outside the generator reads double check, so it is a local. Mate vs stalemate (`searcher.dart:157`) only needs check status when the move list is empty, so the caller asks the board: `count == 0 ? (board.isInCheck() ? mateScore + ply : 0) : ...`. The generator is then a pure function of the board with no stale state.
- **No `isInCheck(board)` on the generator.** Check status is a question about the position, so it lives on `Board` (`board.isInCheck()`), usable by search, UCI and the UI. Qsearch (`searcher.dart:204`) calls it before generating, as now. The generator and `Board.isInCheck()` share one attack test, `isAttacked(sq, byColour, occ)` (see step 2), so there is a single copy.
- **No "in check forces quiet moves" override.** `capturesOnly: true` means exactly that. The old override only existed to serve callers; qsearch already generates the full list itself when in check (`searcher.dart:214`, `:226`) and filters with `_capturesOnly`. Dropping it also removes the perft "captures" column mismatch, because a pure capture count becomes possible.
- The `isInCheck == inCheck` consistency assertion in `v12_engine.dart:98` goes away, since there is only one source of truth.

**Facts you need first:**

- `board.pieceBB[piece]` is indexed by full piece code (`Piece.knight | colourConst`, colourConst 0 white / 8 black). `board.colourBB[0]` is white, `[1]` is black.
- `us = board.whiteToPlay ? 0 : 1`, `them = 1 - us`, `ourC = us * 8`, `theirC = them * 8`.
- `pawnAttacks[us * 64 + sq]` are the squares a pawn of colour `us` on `sq` attacks. The squares from which an enemy pawn attacks `sq` are `pawnAttacks[us * 64 + sq] & theirPawns`.
- `between[a * 64 + b]` is strictly between, 0 if not aligned. `line[a * 64 + b]` is **only the segment from a to b, endpoints included**, not the full edge-to-edge line. For pins you therefore need the king to pinner segment (step 5).
- **Prerequisite (M2):** the generator reads `board.castling` and `board.epSquare`, which `makeMove` / `unMakeMove` maintain (M2 `makeMove` steps 5 and 6). They must be correct after every move, not just after `fromFEN`.
- Move flags for `Move.encode(from, to, flag)`: 1 en passant, 2 castling, 3 double push, 4 to 7 promotion to Q, N, R, B. Captures carry no flag.
- Loop idiom: `while (bb != 0) { final sq = BitOps.lsb(bb); bb &= bb - 1; ... }`.

### Build order

Do the steps in order. After each one, run the oracle (see "Testing as you go") and expect it to pass only for the cases the finished steps cover, so build the test to compare per piece type, or accept failures for the missing pieces.

**Step 1: setup and checkers.**
Read `us`, `them`, `ourBB`, `theirBB`, `occ = ourBB | theirBB`, `ksq = lsb(pieceBB[king | ourC])`. Then:

```
checkers = (knightAttacks[ksq] & theirKnights)
         | (pawnAttacks[us * 64 + ksq] & theirPawns)
         | (rookAttacks(ksq, occ)   & (theirRooks | theirQueens))
         | (bishopAttacks(ksq, occ) & (theirBishops | theirQueens))
inCheck       = checkers != 0                       // local variable
inDoubleCheck = inCheck && (checkers & (checkers - 1)) != 0   // local variable
quiet         = !capturesOnly
```

`x & (x - 1)` clears the lowest set bit, so a non-zero result means two or more checkers. There is deliberately no `|| inCheck` here (see the API notes): in captures-only mode while in check, only capturing evasions are returned.
*Check:* temporarily compare your local `inCheck` / `inDoubleCheck` with the old generator's in the oracle test.

**Step 2: a shared `isAttacked(sq, occ, us)` and `Board.isInCheck()`.**
True if any enemy piece attacks `sq` with the given occupancy: knights, pawns (`pawnAttacks[us * 64 + sq]`), the enemy king (`kingAttacks[sq]`), rooks or queens via `rookAttacks`, bishops or queens via `bishopAttacks`. Early return on the first hit. Put it somewhere both `Board` and the generator can reach (a method on `Board` using shared static `AttackTables` / `Sliders`, or a small static helper class). `board.isInCheck()` is then `isAttacked(kingSquare(us), occ, us)`. Use it for king moves and castling in the generator.
*Check:* `board.isInCheck()` equals the old `MoveGenerator.isInCheck(board)` over the playouts.

**Step 3: king moves.**
`targets = kingAttacks[ksq] & ~ourBB`, and `& theirBB` if `capturesOnly`. For each target the move is legal if `!_attacked(target, occ ^ (1 << ksq), us)`. Removing the king from the occupancy stops it "hiding" behind itself on a slider's ray (rook on a1, king on c1: d1 must count as attacked). This replaces the old attack-map special case. Then `if (inDoubleCheck) return moves;`.
*Check:* positions with only a king and a few enemy pieces. Oracle passes on king-only positions.

**Step 4: check mask.**
Not in check: `checkMask = -1` (all ones). In check (single): `checker = lsb(checkers)`, `checkMask = between[ksq * 64 + checker] | checkers`. For a knight or pawn checker `between` is 0, so the mask is just the checker square. Every non-king move must land inside `checkMask`. That covers capturing the checker and blocking.

**Step 5: pins.**
Squares of our pieces that are the only blocker between the king and an enemy slider.

```
snipers = (rookAttacks(ksq, 0)   & (theirRooks   | theirQueens))
        | (bishopAttacks(ksq, 0) & (theirBishops | theirQueens))
for each sniper s:
  b = between[ksq * 64 + s] & occ
  if b has exactly one bit && (b & ourBB) != 0:
     pinned |= b
     pinRay[lsb(b)] = between[ksq * 64 + s] | (1 << s)
```

`pinRay` is a preallocated `Uint64List(64)` field. A pinned piece may only move within its pin ray (king excluded, pinner included, so it can capture the pinner). **Do not use `line[ksq * 64 + from]` for this**: that table stops at `from`, so a pinned piece could never capture its pinner. This was a real bug found by the oracle. `pinRay` entries are only read when the `pinned` bit is set, so no clearing is needed.

**Step 6: target mask.**
`targets = ~ourBB & checkMask`, and `& theirBB` if `capturesOnly`.

**Step 7: knights.**
`bb = pieceBB[knight | ourC] & ~pinned` (a pinned knight can never move). For each knight, emit `knightAttacks[from] & targets`. Write a small `_addMoves(from, attacks)` that loops the bits and calls `Move.encode(from, to)`.

**Step 8: bishops, rooks, queens.**
For each piece, `attacks = sliders.xAttacks(from, occ) & targets`. If `(pinned >>> from) & 1` is set, also `& pinRay[from]`. Emit with `_addMoves`.
*Check:* oracle passes on positions without pawns, castling or en passant.

**Step 9: pawns.**
Loop per pawn (simplest to get right). Per colour: `dir = us == 0 ? -8 : 8`, `startRank = us == 0 ? 6 : 1`, `promoRank = us == 0 ? 1 : 6` (the rank a pawn stands on one step before promoting). `allowed = checkMask & (pinned ? pinRay[from] : -1)`.

- Pushes (only if `!capturesOnly`): `one = from + dir` must be empty and in `allowed`. From `startRank`, `two = one + dir` must also be empty and in `allowed`, with flag 3. Note `two` is only tried when `one` is empty, even if `one` itself is not in `allowed` (blocking can happen on the second square).
- Captures: `pawnAttacks[us * 64 + from] & theirBB & allowed`.
- If the pawn is on `promoRank`, emit four moves per target with flags 4 to 7 instead of one. Quiet promotions only appear when `!capturesOnly`, capture promotions always do.

**Step 10: en passant.**
If `board.epSquare >= 0`: `ep` is the target square and `capSq = ep + (us == 0 ? 8 : -8)` is the captured pawn. Candidates are `pawnAttacks[them * 64 + ep] & ourPawns`. Test each one exactly by playing it on a copy of the occupancy:

```
occ2 = (occ ^ (1 << from) ^ (1 << capSq)) | (1 << ep)
attacked = (knightAttacks[ksq] & theirKnights) != 0
        || (pawnAttacks[us * 64 + ksq] & (theirPawns & ~(1 << capSq))) != 0
        || (rookAttacks(ksq, occ2)   & (theirRooks   | theirQueens)) != 0
        || (bishopAttacks(ksq, occ2) & (theirBishops | theirQueens)) != 0
```

Legal if not attacked. This one test handles: the horizontal discovered check when two pawns leave the same rank, a diagonal pin, and a check by the double-pushed pawn itself (removing `capSq` from the pawns). Do not try to reuse `checkMask` or `pinned` here. Emit flag 1.

**Step 11: castling.**
Only when `!inCheck && !capturesOnly`. `base = us == 0 ? 56 : 0`, require `ksq == base + 4`, rights from `board.castling` (8 = WK, 4 = WQ, 2 = BK, 1 = BQ).

- King side: right set, `base + 5` and `base + 6` empty, neither attacked. Emit `ksq -> base + 6`, flag 2.
- Queen side: right set, `base + 1`, `base + 2`, `base + 3` empty, only `base + 2` and `base + 3` attacked-tested (b-file may be attacked). Emit `ksq -> base + 2`, flag 2.

Use `isAttacked(sq, occ, us)` for the tests.

### Testing as you go

`test/engines/v12/bitboard_move_generator_test.dart` has two parts:

1. **Perft** through `makeMove` / `unMakeMove` on the six standard positions. Reference counts: startpos d4 = 197281, kiwipete d3 = 97862, position 3 d4 = 43238, position 4 d3 = 9467, position 5 d3 = 62379, position 6 d3 = 89890.
2. **Oracle**: random playouts from those six FENs, comparing `Set<int>` of `move.value` from both generators, plus `board.isInCheck()` against the old `isInCheck`. Full mode compares directly. **Captures-only mode differs by design when in check**: the old generator adds quiet evasions there and the new one does not. So in check, compare the new output with the old output filtered to captures (target occupied, or en passant, or promotion captures); when not in check, compare directly. On a mismatch, print the FEN, the missing moves and the extra moves. That finds a bug far faster than a perft number. Do not compare Dart `Set`s with `==`: it checks identity. Compare lengths and `difference`.

Incremental strategy: while a step is unfinished, the oracle will fail on positions that use the missing piece. Either test against a subset FEN (for example king and knights only) or temporarily filter both move lists by the piece types you have implemented.

### Pitfalls

- `>>` vs `>>>`: bit 63 is set for a1-h1 style masks, so always use `>>>`.
- A pinned piece can still capture its pinner: use the king to pinner segment, not `line`.
- Captures-only in check returns only capturing evasions (no override). Qsearch must generate the full list itself when in check. The perft harness's captures column (`v12_engine.dart` `_perft`) previously relied on the old override, so its expected counts may need checking once it uses the new generator.
- Double pushes: the middle square must be empty, and the landing square must be in `allowed`, tested independently of the single push.
- Castling needs the king not in check, but not that the rook square is safe, and the b-file square on the queen side may be attacked.
- Reuse the shared `AttackTables` and `Sliders` (static finals) so constructing a generator is free.

### Done when

The new test passes (perft counts and oracle), `dart analyze` is clean, and nothing outside the new file and test changed. Swapping callers and deleting the old generator is M5.

## Milestone 5: switch search, ordering and eval onto the new board and generator (behaviour-preserving)

v11 already has int-backed `Move`s, `scoreMoves` / `pickBest` ordering, and a TT that stores moves directly, so most of the original "port to int moves" work is done. What remains is moving the callers onto the bitboard generator and removing per-node allocation. Do it in this order, running perft and the mate tests after each step:

1. **Swap the generator.** In `searcher.dart`, `v12_engine.dart` and `lib/screens/engine_test_screen.dart`, replace `MoveGenerator` with `BitboardMoveGenerator`. Rename `includeQuietMoves: false` to `capturesOnly: true`.
2. **Mate vs stalemate** (`searcher.dart` around `:157`): `moveGenerator.inCheck` no longer exists. Use `board.isInCheck()` when the move list is empty.
3. **Qsearch** (`searcher.dart` around `:204`): replace `moveGenerator.isInCheck(board)` with `board.isInCheck()`. The generator no longer forces quiet moves in check. The existing code already generates the full list when in check and filters with `_capturesOnly`; keep that exactly, and keep the V11 semantics for evasions and mate detection.
4. **Perft harness** (`v12_engine.dart` `_perft`): drop the `isInCheck == inCheck` assertion. Re-derive the expected captures column, because captures-only in check now returns only capturing evasions.
5. **Remove per-node allocation.** Change the generator output from a new `List<Move>` to a caller-supplied `Int32List` (`int generate(Board b, Int32List out, {bool capturesOnly = false})`, storing `move.value`). In `Searcher`, preallocate `List<Int32List> moveBuf` and `scoreBuf`, each `MAX_PLY = 128` entries of 256. Root keeps its own buffer, and "best move first" reordering becomes a swap-to-front. `MoveOrdering` then takes `(Int32List moves, int count, ...)`.
6. **Time check:** compare `_stopwatch.elapsedMicroseconds` to a precomputed int rather than allocating a `Duration` (`searcher.dart` `_timeLimit`).
7. **`MoveOrdering`:** same scores as V11 (TT move 10000, promotion `promotion*10`, MVV-LVA `pieceValues[type(captured)]*10 - pieceValues[type(moving)]`, en passant victim valued as `Piece.none`). Check whether the `.sort` at `move_ordering.dart:33` and any `Map` lookups are still in the hot path and replace them with a `const List<int>` and the `pickBest` loop.
8. **`TranspositionTable`:** unchanged. Replacement policy stays as it is, so V12 remains a pure speed comparison. The fail-low `Move.invalid` overwrite fix waits for V13.
9. **`Evaluator`:** rewrite the counting with bitboards but produce **identical** scores:
   - Counts: `popCount(pieceBB[...])`.
   - PST sums: pop-lsb over each piece bitboard, using index `sq` for white and `sq ^ 56` for black, as V11 does.
   - Light/dark bishops: `popCount(bishops & LIGHT_SQUARES)`.
   - King squares: `lsb`.
   - The material, phase, insufficient-material, mop-up and tapered-PST logic is copied verbatim.
   - No per-call list allocation: use fields or a reused `Int32List`.
10. **Delete the old generator** (`core/move_generator.dart`, `precompute_data.dart` if nothing else uses it). Move the oracle test to compare against `lib/engines/v11`'s generator, which stays frozen. Rename `BitboardMoveGenerator` to `MoveGenerator` if you want call sites unchanged.

## Milestone 6: engine wrapper, registry, docs

- `V12Engine` and the `'v12'` registry entry already exist, which puts v12 under the perft and mate tests. Check `displayName` (`'V12 - Bitboards'`) and the opening-book logic still work after M5.
- Parse `uciMoves` by generating legal moves into a buffer and matching `move.uci`.
- Add the README line `**v12** - Bitboard board representation and move generation (+N ELO)`. Fill N in after the match.
- Restore any entries in `engine_registry.dart` that were commented out for faster testing.

## Milestone 7: magic bitboards (measured, optional but expected to help)

- **`tool/generate_magics.dart`**: for each square, build relevance masks (rays excluding edges), then do a random sparse-number search with a fixed seed until there are no destructive collisions. It writes `lib/engines/v12/core/magic_numbers.dart` with const `rookMagics`, `bishopMagics` and per-square bit counts. **Generate them for this a8 = 0 mapping**: published magics assume a1 = 0.
- **`sliders.dart`**: `rookAttacks(sq, occ) = rookTable[rookOffset[sq] + (((occ & rookMask[sq]) * rookMagic[sq]) >>> rookShift[sq])]`. The tables are one `Uint64List` each (about 102,400 rook and 5,248 bishop entries, under 1 MB). They're filled at first use from the classical routine, which takes a few ms per isolate.
- Keep the classical implementation in `sliders.dart` as `rookAttacksSlow`. It's the test oracle.
- Benchmark classical vs magic, and keep magic only if it's faster in AOT. Expect around 1.3–2×.

## Milestone 8: validate strength

- Run `tool/bench.dart v12` against the V11 numbers and check the NPS targets.
- Run a match in the match manager: V12 vs V11, 100 ms, 1000+ games, with the existing opening book. Record the Elo in the README.

---

## Tests: `test/engines/v12/`

Test files can import both v11 and v12, because they aren't covered by snapshot purity. Existing: `bitboard_test.dart` (tests 1, 2, 4, 5 in part) and `sliders_test.dart` (test 3). M4 adds `bitboard_move_generator_test.dart` (tests 6, 7 and perft). **V11 is a perfect oracle**: its generator already passes perft.

1. **BitOps**: `popCount`, `lsb` and `msb` against naive loops on 10k random 64-bit values. Include ones with bit 63 set, 0 for popcount, and single-bit values.
2. **Leaper tables**: for every square, the `knightAttacks`/`kingAttacks`/`pawnAttacks` bitboards equal the V11 `PrecomputeData` lists converted to bitboards.
3. **Sliders**: classical rook/bishop attacks vs a naive square-by-square ray walk on 10k random occupancies per square. After M7, magic vs classical too.
4. **`between` / `line`**: spot checks, for example a8–h1 diagonal, e1–e8 file, a1–c2 (not aligned → 0).
5. **Board invariants fuzz**: random playouts of 200 plies from each perft FEN, repeated. At every node check:
   - `zobristKey == Zobrist.getZobristForBoard(board)`
   - `pieceBB` / `colourBB` agree with `squares`
   - after `unMakeMove`, every field (including `castling`, `epSquare`, `halfMove`, `plyCount`) equals the snapshot taken before `makeMove`

   The debug screen (`bitboard_test_screen.dart`) has this fuzz. Include null-move make/unmake once `makeNullMove` exists.

6. **Move generation oracle**: on all positions visited in (5), about 50k:
   - the set of moves from V12 `generateLegalMoves` equals the old generator's, in full mode; in captures-only mode compare directly when not in check, and against the old output filtered to captures when in check
   - `board.isInCheck()` equals the old generator's `isInCheck`

   On failure, print the FEN, the missing moves and the extra moves. That pinpoints a bug far faster than perft numbers.

7. **Targeted edge-case FENs** (also run through the oracle):
   - ep capture exposing a horizontal check: `8/8/8/KPp4r/8/8/8/7k w - c6 0 1`
   - ep that evades a check from the double-pushed pawn
   - castling through or out of check
   - castling after the rook is captured on its home square
   - promotion with and without capture, including in captures-only mode
   - a pinned pawn that can only capture its pinner
8. **Eval oracle**: V12 `Evaluator.evaluate` equals V11 `Evaluator.evaluate` for every position in (5).
9. **Repetition**: play `Nf3 Nf6 Ng1 Ng8` from the start and check `isRepetition()` at every ply (false, false, false, true). `hashHistory` no longer exists in v12.
10. **Automatic via the registry**:
    - `perft_all_versions_test.dart` (all 6 positions, including Position 5/6 depth 5)
    - `mate_all_versions_test.dart`
    - `snapshot_purity_test.dart`
    - `adapter_test.dart`

Run with `flutter test test/engines/v12`, then the full `flutter test`.

## Order of work, with checkpoints

| Step                     | Done when                                                                               | Rough size |
| ------------------------ | --------------------------------------------------------------------------------------- | ---------- |
| M0 bench                 | V11 numbers recorded                                                                     | ½ day      |
| M1 bitops + tables       | tests 1–2, 4 green                                                                      | ½ day      |
| M2 board + zobrist       | test 5 green (debug screen fuzz)                                                         | 1 day      |
| M3 sliders               | test 3 green                                                                            | ½ day      |
| M4 generator             | tests 6–7 green, then perft green                                                       | 1–2 days   |
| M5 search/eval port      | test 8, 9 green; mate tests green; bench shows the NPS gain                             | 1 day      |
| M6 wrapper/registry/docs | full `flutter test` green                                                               | ½ day      |
| M7 magics                | slider oracle green; bench shows the gain                                               | ½–1 day    |
| M8 match                 | Elo recorded in README                                                                  | match time |

## Risks and how they're handled

- **Shift and sign bugs** (`>>` vs `>>>`, file wrap on diagonal shifts): BitOps and table tests, plus the generator oracle.
- **Orientation confusion (a8 = 0)**: constants are defined once in `bitboard.dart`, plus a `toAscii()` debug printer. Tests compare against V11, which uses the same mapping.
- **En passant and castling edge cases**: targeted FENs and the oracle. Perft Position 3 covers the ep horizontal pin, and Kiwipete covers castling.
- **Behaviour drift that would muddy the Elo comparison**: eval oracle and identical ordering scores. TT, qsearch and root logic are copied verbatim. Only move tie-order and hash-collision behaviour can differ.
- **Web builds**: `Uint64List` and 64-bit literals are unsupported, but the engine already needs isolates. Document this in the README.

## After V12 (unchanged from the review, now on the int-move API)

- V13, search: null move (uses `makeNullMove`), killers + history, PVS, check extension, TT fail-low move fix, aspiration windows.
- V14: LMR + futility/RFP.
- V15 eval, made cheap by bitboards: PeSTO, passed/isolated/doubled pawns via file masks, mobility via `popCount(attacks)`, king safety, SEE in qsearch.
- Later: Texel tuning.
