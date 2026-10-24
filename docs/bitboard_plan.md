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
- **`line`**: `Uint64List(64*64)`. The segment from `a` to `b`, both endpoints included, when aligned, else 0. It is **not** edge to edge, so don't use it to restrict pinned pieces (see M4 step 6).
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
- **No `isInCheck(board)` on the generator.** Check status is a question about the position, so it lives on `Board` (`board.isInCheck()`), usable by search, UCI and the UI without needing a generator. Qsearch (`searcher.dart:204`) calls it before generating, as now. The generator and `Board.isInCheck()` share one function, `Board.attackersTo(sq, occ, by)` (steps 1 to 3), so there is a single copy of the attack logic.
- **No "in check forces quiet moves" override.** `capturesOnly: true` means exactly that. The old override only existed to serve callers; qsearch already generates the full list itself when in check (`searcher.dart:214`, `:226`) and filters with `_capturesOnly`. Dropping it also removes the perft "captures" column mismatch, because a pure capture count becomes possible.
- The `isInCheck == inCheck` consistency assertion in `v12_engine.dart:98` goes away, since there is only one source of truth.

**Facts you need first:**

- `board.pieceBB[piece]` is indexed by full piece code (`Piece.knight | colourConst`, colourConst 0 white / 8 black). `board.colourBB[0]` is white, `[1]` is black.
- `us = board.whiteToPlay ? 0 : 1`, `them = 1 - us`, `ourC = us * 8`, `theirC = them * 8`.
- `pawnAttacks[us * 64 + sq]` are the squares a pawn of colour `us` on `sq` attacks. The squares from which an enemy pawn attacks `sq` are `pawnAttacks[us * 64 + sq] & theirPawns`.
- `between[a * 64 + b]` is strictly between, 0 if not aligned. `line[a * 64 + b]` is **only the segment from a to b, endpoints included**, not the full edge-to-edge line. For pins you therefore need the king to pinner segment (step 6).
- **Prerequisite (M2):** the generator reads `board.castling` and `board.epSquare`, which `makeMove` / `unMakeMove` maintain (M2 `makeMove` steps 5 and 6). They must be correct after every move, not just after `fromFEN`.
- Move flags for `Move.encode(from, to, flag)`: 1 en passant, 2 castling, 3 double push, 4 to 7 promotion to Q, N, R, B. Captures carry no flag.
- Loop idiom: `while (bb != 0) { final sq = BitOps.lsb(bb); bb &= bb - 1; ... }`.

### Build order

Each step says **what** you add, **why**, **what it gives you**, then the code in small pieces, then how to check it. Do them in order. After each one, open the Generator tab and use the kind filter so you only compare the parts that exist.

All snippets use these names: `tables` (`AttackTables`), `sliders` (`Sliders`), `pieceBB = board.pieceBB`. The generator is `generate(Board board, {bool capturesOnly = false})`.

---

**Step 0: scaffold and read the position.**

*What:* the first lines of `generate`: reset `moves`, work out which side is us, and fetch the bitboards everything else needs.
*Why:* every later step needs the same handful of values. Compute them once, with the right indexing. This is where a lot of bugs start, because two arrays use different indexes (see the table below).
*Gives you:* a generator that runs on both colours and returns an empty list.

```dart
List<Move> generate(Board board, {bool capturesOnly = false}) {
  moves = [];
  final pieceBB = board.pieceBB;

  final us = board.whiteToPlay ? 0 : 1;   // colour INDEX, for colourBB and the pawn tables
  final them = 1 - us;
  final ourC = us * 8;                    // colour CODE (0 or 8), for building piece codes
  final theirC = them * 8;

  final ourBB = board.colourBB[us];       // NOT colourBB[ourC]: that is index 8 for black and throws
  final theirBB = board.colourBB[them];
  final occ = ourBB | theirBB;            // every occupied square
  final ksq = board.kingSquare(ourC);     // our king's square

  return moves;
}
```

| Array | Index with | Example |
| --- | --- | --- |
| `colourBB` | `us` / `them` (0 or 1) | `board.colourBB[us]` |
| `pieceBB` | full piece code | `pieceBB[Piece.knight \| ourC]` |
| `pawnAttacks` | `colour * 64 + sq` (0 or 1) | `tables.pawnAttacks[us * 64 + sq]` |

*Check:* Generator tab shows no red error text on a white-to-move and a black-to-move preset.

---

**Step 1: `attackersTo(sq, occ, by)`.**

*What:* one function that returns a bitboard of **every piece of colour `by` that attacks `sq`**, given an occupancy `occ`.
*Why:* "who attacks this square?" is asked in four places: the checkers (who attacks my king), king-move safety, castling squares, and `isInCheck`. Writing it once means one place to get wrong and one place to test. It returns the whole bitboard rather than a yes/no so the same code gives you the checkers *and* how many there are.
*Gives you:* the building block for steps 2, 3, 4 and 11.

It lives on `Board`, which needs the shared tables (see step 2 for why on `Board`). Give `Board` one shared copy of the tables and sliders and let the generator use them too:

```dart
// board.dart
static final AttackTables tables = AttackTables();
static final Sliders sliders = Sliders(tables);
static final Int32List _castleMask = tables.castleMask;   // replaces the separate AttackTables() you build now
```

Now the function, one line per piece type. Read each line as "which of *their* pieces could attack `sq`":

```dart
/// All pieces of colour index [by] attacking [sq] when the board has occupancy [occ].
int attackersTo(int sq, int occ, int by) {
  final byC = by * 8;                                   // piece-code colour bits
  final queens = pieceBB[Piece.queen | byC];
  return (tables.knightAttacks[sq] & pieceBB[Piece.knight | byC])
       | (tables.pawnAttacks[(1 - by) * 64 + sq] & pieceBB[Piece.pawn | byC])
       | (tables.kingAttacks[sq] & pieceBB[Piece.king | byC])
       | (sliders.rookAttacks(sq, occ) & (pieceBB[Piece.rook | byC] | queens))
       | (sliders.bishopAttacks(sq, occ) & (pieceBB[Piece.bishop | byC] | queens));
}
```

Why each line works:
- **Knights and kings** are symmetric. A knight attacks `sq` exactly when `sq` is a knight's jump away from it, so look up the jumps *from `sq`* and intersect with their knights.
- **Pawns** are not symmetric. Pawns attack forwards only, so take the squares an enemy pawn would have to stand on: those are the squares a pawn of the **opposite** colour on `sq` would attack. That is why the index is `(1 - by) * 64 + sq`, not `by * 64 + sq`.
- **Sliders**: pretend there is a rook on `sq` and see which squares it reaches (stopping at blockers). Any of their rooks or queens on those squares attacks `sq`. Same for bishops. Queens are in both.

*Check:* add a test that for every square and both colours on playout positions, `attackersTo(sq, occ, by)` equals a naive version. The reference code in `generator_test_tab.dart` (`_attackersOf`) is exactly that naive version, so you can copy it into a test.

---

**Step 2: `Board.isInCheck()`.**

*What:* a one-line method on `Board` that answers "is the side to move in check?".
*Why on `Board` and not the generator:* check is a fact about the *position*, not about move generation. Several callers need it **without generating moves**: qsearch decides whether to stand pat before it generates anything (`searcher.dart` around `:204`), mate vs stalemate is decided after generation returns empty, and the UI and any future check extension want it too. If it lived on the generator, every one of those callers would need a generator and would have to run it, or the generator would hold "last result" state that can go stale. It is not required that it be on `Board`; it just needs to be callable with only a board, and `Board` already owns everything it reads.
*Is it the same as step 3?* Same ingredient, different question. `isInCheck` only needs yes or no. The checkers step needs the **bitboard** (which pieces, and how many). Both are `attackersTo` on the king square, so `isInCheck` is just "is that bitboard non-zero".

```dart
bool isInCheck() {
  final us = whiteToPlay ? 0 : 1;
  return attackersTo(kingSquare(us * 8), colourBB[0] | colourBB[1], 1 - us) != 0;
}
```

*Gives you:* the single source of truth for check, used by qsearch, mate detection and the oracle.
*Check:* compare `board.isInCheck()` with the old `MoveGenerator.isInCheck(board)` over random playouts. The Generator tab's reference panel also prints "IN CHECK" for the current position.

---

**Step 3: checkers and double check.**

*What:* in `generate`, ask for the checkers as a bitboard and derive two flags.
*Why:* the check mask (step 5) needs to know *which* piece is giving check, and double check (two or more checkers) means only the king can move, so everything else can be skipped. A plain `isInCheck()` bool throws that information away.
*Gives you:* `checkers`, `inCheck`, `inDoubleCheck` as local variables.

```dart
final checkers = board.attackersTo(ksq, occ, them);
final inCheck = checkers != 0;
final inDoubleCheck = (checkers & (checkers - 1)) != 0;
```

`checkers & (checkers - 1)` clears the lowest set bit, so it is non-zero exactly when two or more bits were set. A king is never adjacent to the enemy king in a legal position, so the king term in `attackersTo` never adds a fake checker.
*Check:* the generator already has debug fields `lastCheckers`, `lastCheckMask` and `lastPinned` (reset to `null` at the start of every `generate`). Assign `lastCheckers = checkers;` here. The Generator tab then shows `checkers  OK` or `DIFFERS` with your value next to the naive reference, and on the Checkers layer squares where the two differ turn orange.

---

**Step 4: king moves.**

*What:* generate the king's legal moves.
*Why first:* it is the one piece that can always move, it works in every situation including double check, and it needs no masks. It also exercises `attackersTo` immediately.
*Gives you:* correct king play, and an early return in double check.

```dart
int kingTargets = tables.kingAttacks[ksq] & ~ourBB;    // adjacent squares not occupied by our own pieces
if (capturesOnly) kingTargets &= theirBB;               // captures only: keep enemy-occupied squares

final occNoKing = occ ^ (1 << ksq);                     // the board as if our king had left
while (kingTargets != 0) {
  final to = BitOps.lsb(kingTargets);
  kingTargets &= kingTargets - 1;
  if (board.attackersTo(to, occNoKing, them) == 0) {
    moves.add(Move.encode(ksq, to));
  }
}
if (inDoubleCheck) return moves;                        // nothing else can help
```

Why `occNoKing`: a rook on a1 checks a king on c1 along the rank. If the king steps to d1 with the king still counted in `occ`, the rook's ray stops at c1 and d1 looks safe. It is not: once the king moves, the ray runs on. Removing the king from the occupancy fixes that.
*Check:* Generator tab, filter **King only**. Presets "Rook check along rank", "Pawn check", "Knight check", "Double check" and the start position (no moves).

---

**Step 5: check mask.**

*What:* a bitboard of the squares that a **non-king** piece is allowed to move to.
*Why:* in single check, a non-king move is only legal if it captures the checker or blocks the line between checker and king. One mask handles both, so you do not need separate "in check" branches in every piece loop.
*Gives you:* `checkMask`, applied to every other piece.

```dart
int checkMask = -1;                                      // not in check: every square allowed (all ones)
if (inCheck) {
  final checker = BitOps.lsb(checkers);                  // exactly one checker here
  checkMask = tables.between[ksq * 64 + checker] | checkers;
}
```

`between` is the squares strictly between king and checker (blocks), `| checkers` adds the checker's square (captures). For a knight or pawn checker `between` is 0, so only capturing is allowed, which is right, since you cannot block those.
*Check:* assign `lastCheckMask = checkMask;`. The Generator tab compares it with the reference (`-1` shows as "all squares") and marks differing squares on the Check mask layer.

---

**Step 6: pins.**

*What:* find our pieces that are the only thing between our king and an enemy slider, and for each, the line it must stay on.
*Why:* a pinned piece may only move along the line between king and pinner (including capturing the pinner). Without this, we would generate moves that expose our king.
*Gives you:* `pinned` (bitboard of pinned pieces) and `_pinRay[sq]` (where each may go).

Add a field: `final Uint64List _pinRay = Uint64List(64);`

First find the enemy sliders that *could* pin, by looking out from the king on an empty board:

```dart
final theirQueens = pieceBB[Piece.queen | theirC];
final theirRQ = pieceBB[Piece.rook | theirC] | theirQueens;
final theirBQ = pieceBB[Piece.bishop | theirC] | theirQueens;

int snipers = (sliders.rookAttacks(ksq, 0) & theirRQ)
            | (sliders.bishopAttacks(ksq, 0) & theirBQ);
```

Then for each sniper, count what stands between it and the king:

```dart
int pinned = 0;
while (snipers != 0) {
  final sniper = BitOps.lsb(snipers);
  snipers &= snipers - 1;

  final between = tables.between[ksq * 64 + sniper];
  final blockers = between & occ;
  // exactly one piece in the way, and it is ours: that piece is pinned
  if (blockers != 0 && (blockers & (blockers - 1)) == 0 && (blockers & ourBB) != 0) {
    pinned |= blockers;
    _pinRay[BitOps.lsb(blockers)] = between | (1 << sniper);   // may move anywhere on the line, or capture the pinner
  }
}
```

Do **not** use `tables.line[ksq * 64 + from]`: that table only covers the segment from king to the piece, so the pinned piece could never capture its pinner. `_pinRay` entries are only read when the `pinned` bit is set, so they need no clearing.
*Check:* assign `lastPinned = pinned;`. The Generator tab compares it with the reference and marks differences on the Pinned pieces layer; the Pin rays layer shows the reference rays. Presets: pinned knight, rook, bishop, pawn.

---

**Step 7: target mask and knights.**

*What:* combine the masks into one `targets`, then generate knight moves.
*Why:* `targets` is the one filter every non-king, non-pawn piece shares: not onto our own pieces, and (in check) only onto check-resolving squares, and (captures-only) only onto enemy pieces. A pinned knight can never move (a knight cannot stay on a line), so remove pinned knights up front.
*Gives you:* a helper you reuse for every piece.

```dart
int targets = ~ourBB & checkMask;
if (capturesOnly) targets &= theirBB;
```

A tiny helper that turns an attack bitboard into moves:

```dart
void _addMoves(int from, int attacks) {
  while (attacks != 0) {
    final to = BitOps.lsb(attacks);
    attacks &= attacks - 1;
    moves.add(Move.encode(from, to));
  }
}
```

Knights:

```dart
int knights = pieceBB[Piece.knight | ourC] & ~pinned;
while (knights != 0) {
  final from = BitOps.lsb(knights);
  knights &= knights - 1;
  _addMoves(from, tables.knightAttacks[from] & targets);
}
```

*Check:* filter **Knight**. Presets "Knight check", "Rook check (block with N or B)", "Pinned knight".

---

**Step 8: bishops, rooks, queens.**

*What:* the same loop for the three sliders, with attacks from `Sliders` and the pin ray applied.
*Why the pin ray:* a pinned slider may still move, but only along its pin line.
*Gives you:* all piece moves except pawns and special moves.

One helper covers all three, taking the attack function:

```dart
void _slideMoves(int bb, int Function(int sq, int occ) attacksFor, int occ, int targets, int pinned) {
  while (bb != 0) {
    final from = BitOps.lsb(bb);
    bb &= bb - 1;
    int attacks = attacksFor(from, occ) & targets;
    if ((pinned >>> from) & 1 == 1) attacks &= _pinRay[from];   // stay on the pin line
    _addMoves(from, attacks);
  }
}
```

and three calls:

```dart
_slideMoves(pieceBB[Piece.bishop | ourC], sliders.bishopAttacks, occ, targets, pinned);
_slideMoves(pieceBB[Piece.rook   | ourC], sliders.rookAttacks,   occ, targets, pinned);
_slideMoves(pieceBB[Piece.queen  | ourC], sliders.queenAttacks,  occ, targets, pinned);
```

*Check:* filters **Bishop / Rook / Queen**. Presets "Pinned rook", "Pinned bishop", "Bishop check".

---

**Step 9: pawns.**

*What:* single pushes, double pushes, captures, and promotions.
*Why a per-pawn loop:* it is the simplest to get right. Pawns are the piece with the most special rules (direction by colour, start rank, promotion), so correctness first; shift-based set-wise generation is a later optimisation.
*Gives you:* everything except en passant and castling.

Per-colour constants, and the squares a pawn move is *allowed* to land on:

```dart
final dir = us == 0 ? -8 : 8;               // white moves towards rank 8 (lower index)
final startRank = us == 0 ? 6 : 1;          // rank index where double pushes start
final promoRank = us == 0 ? 1 : 6;          // rank index one step before promotion

int pawns = pieceBB[Piece.pawn | ourC];
while (pawns != 0) {
  final from = BitOps.lsb(pawns);
  pawns &= pawns - 1;
  final rank = from >> 3;
  // check mask, narrowed to the pin line if this pawn is pinned
  final allowed = checkMask & ((pinned >>> from) & 1 == 1 ? _pinRay[from] : -1);
```

Pushes (never in captures-only mode):

```dart
  if (!capturesOnly) {
    final one = from + dir;
    if ((occ >>> one) & 1 == 0) {                         // square ahead is empty
      if ((allowed >>> one) & 1 == 1) {
        rank == promoRank ? _promotions(from, one) : moves.add(Move.encode(from, one));
      }
      if (rank == startRank) {
        final two = one + dir;
        if ((occ >>> two) & 1 == 0 && (allowed >>> two) & 1 == 1) {
          moves.add(Move.encode(from, two, 3));           // flag 3 = double push
        }
      }
    }
  }
```

Note the double push is tested separately against `allowed`: when in check, the single push may not block but the double push might.

Captures:

```dart
  int captures = tables.pawnAttacks[us * 64 + from] & theirBB & allowed;
  while (captures != 0) {
    final to = BitOps.lsb(captures);
    captures &= captures - 1;
    rank == promoRank ? _promotions(from, to) : moves.add(Move.encode(from, to));
  }
}   // end of the pawn loop
```

```dart
void _promotions(int from, int to) {
  for (int flag = 4; flag <= 7; flag++) {                 // 4 Q, 5 N, 6 R, 7 B
    moves.add(Move.encode(from, to, flag));
  }
}
```

*Check:* filter **Pawn**. Presets "Pinned pawn", "Position 4" (promotions), and captures-only mode (quiet promotions must not appear).

---

**Step 10: en passant.**

*What:* the en passant capture, tested by actually simulating it.
*Why a simulation:* en passant is the one move that removes **two** pieces from a line at once (the capturing pawn leaves, the captured pawn disappears), which can open a discovered check along a rank that no mask would catch. Playing it on a copy of the occupancy and re-asking "is my king attacked?" covers pins, the horizontal case, and removing a pawn that was giving check, all in one test.
*Gives you:* correct en passant with no special cases.

```dart
final ep = board.epSquare;
if (ep >= 0) {
  final capSq = ep + (us == 0 ? 8 : -8);                  // the pawn being captured
  // our pawns that attack the ep square = squares a THEIR pawn on ep would attack
  int attackers = tables.pawnAttacks[them * 64 + ep] & pieceBB[Piece.pawn | ourC];
  while (attackers != 0) {
    final from = BitOps.lsb(attackers);
    attackers &= attackers - 1;

    // the board after the capture: our pawn moved from -> ep, their pawn on capSq removed
    final occ2 = (occ ^ (1 << from) ^ (1 << capSq)) | (1 << ep);
    final theirPawnsAfter = pieceBB[Piece.pawn | theirC] & ~(1 << capSq);

    final attacked = (tables.knightAttacks[ksq] & pieceBB[Piece.knight | theirC]) != 0
        || (tables.pawnAttacks[us * 64 + ksq] & theirPawnsAfter) != 0
        || (sliders.rookAttacks(ksq, occ2) & theirRQ) != 0
        || (sliders.bishopAttacks(ksq, occ2) & theirBQ) != 0;

    if (!attacked) moves.add(Move.encode(from, ep, 1));   // flag 1 = en passant
  }
}
```

Do not reuse `checkMask` or `pinned` here: the simulation already covers them.
*Check:* filter **EP**. Presets "En passant captures the checking pawn" (legal) and "En passant illegal (horizontal pin)" (must produce no ep move).

---

**Step 11: castling.**

*What:* the two castling moves per side.
*Why last:* it needs `attackersTo`, the rights from `board.castling`, and the check state, and it is self-contained.
*Gives you:* the complete generator.

Rules: not in check, rights present, the squares between king and rook empty, and the squares the king **passes through and lands on** not attacked. The b-file square on the queen side only has to be empty, not safe.

```dart
if (!inCheck && !capturesOnly) {
  final base = us == 0 ? 56 : 0;                          // a1 for white, a8 for black
  if (ksq == base + 4) {                                  // king on its home square
    final kingSideRight = us == 0 ? 8 : 2;
    final queenSideRight = us == 0 ? 4 : 1;

    if (board.castling & kingSideRight != 0 &&
        occ & ((1 << (base + 5)) | (1 << (base + 6))) == 0 &&
        board.attackersTo(base + 5, occ, them) == 0 &&
        board.attackersTo(base + 6, occ, them) == 0) {
      moves.add(Move.encode(ksq, base + 6, 2));           // flag 2 = castling
    }
    if (board.castling & queenSideRight != 0 &&
        occ & ((1 << (base + 1)) | (1 << (base + 2)) | (1 << (base + 3))) == 0 &&
        board.attackersTo(base + 3, occ, them) == 0 &&
        board.attackersTo(base + 2, occ, them) == 0) {
      moves.add(Move.encode(ksq, base + 2, 2));
    }
  }
}
```

Put this after the double-check early return from step 4. That is fine, because castling is illegal in check anyway (`!inCheck`).
*Check:* filter **Castle**. Presets "Kiwipete" and "Position 4", then "Run all presets" and the random playouts button with all kinds enabled.

---

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
