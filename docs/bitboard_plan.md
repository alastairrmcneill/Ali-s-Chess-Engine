# V10: bitboard board and move generator (detailed implementation plan)

## Context

V9 (`lib/engines/v9`) spends most of its time on board bookkeeping rather than searching:

- It tracks attack maps and pin/check rays in `Set<int>`s.
- It rescans all 64 squares on every `generateLegalMoves`.
- It allocates a heap `Move` object for every move and a `GameState` per `makeMove`.
- It updates a `HashMap` for repetitions on every make/unmake.

Matches run at 100 ms/move, so nodes per second (NPS) turns almost directly into depth, and depth into Elo. The goal of V10 is to **replace the board representation and move generator with bitboards and keep the V9 search and eval behaviour as close to identical as possible**. Then the V10-vs-V9 match measures the speed gain alone. Search improvements (null move, killers, PVS, LMR and so on) come afterwards, as V11+, on top of the new API.

Targets, measured in AOT with `dart compile exe`:

- Perft speed at least 5× V9.
- Search NPS at least 3× V9.
- All perft, mate and new oracle tests green.
- Expected about +150–300 Elo vs V9 at 100 ms.

### Constraints found in the repo

- **Snapshot purity** (`test/engines/snapshot_purity_test.dart`): files under `lib/engines/v10/` may import only `dart:*`, `package:ace/engines/v10/...`, `package:ace/chess_core/notation/...` and `package:ace/engines/engine_interface.dart`. All cross-version comparison code must live in `test/`.
- **Registry-driven tests**: `perft_all_versions_test.dart` and `mate_all_versions_test.dart` iterate `EngineRegistry.allIds`. Registering `v10` brings it under perft and mate testing automatically.
- **Square indexing**: `FenPosition`, `UciMove`, `BoardHelper` and the PSTs all use **index 0 = a8, 63 = h1** (rank 8 first). **Keep this mapping**, with bit _i_ = square _i_. That means:
  - "North" (towards rank 8) is index −8, i.e. `>>> 8`.
  - "South" is `<< 8`.
  - East (file+1) is `<< 1`, masked with `~FILE_A`.
  - West is `>>> 1`, masked with `~FILE_H`.
- **Piece codes**: `FenPosition.position` uses V9's codes (type 1–6, white = 0, black = 8; max code 14). Keep `piece.dart` identical so the FEN parser and PSTs work unchanged.
- **Platform**: Dart native `int` is 64-bit two's-complement, and multiplication and `<<` wrap, which is what bitboards and magics need. On **web**, `int` is a JS double and `Uint64List` throws. Engines already run via `Isolate.spawn` (`lib/services/engine_worker.dart`), which web doesn't support, so web is out of scope. Note it in the README.

---

## File layout (new folder `lib/engines/v10/`)

| File                       | Source                               | Purpose                                                                                                                                                    |
| -------------------------- | ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `core/piece.dart`          | copy of v9                           | piece codes, unchanged                                                                                                                                     |
| `core/bitboard.dart`       | new                                  | constants (files, ranks, light squares), `BitOps` (popcount, lsb, msb, popLsb), square helpers, debug `toAscii()`                                          |
| `core/attack_tables.dart`  | new, replaces `precompute_data.dart` | knight/king/pawn attack `Uint64List`s, rays per direction, `between` and `line` tables (flat `Uint64List(4096)`), castling masks                           |
| `core/sliders.dart`        | new                                  | `rookAttacks(sq, occ)` / `bishopAttacks` / `queenAttacks`. Milestone 3 uses the classical ray approach; milestone 7 switches to magics behind the same API |
| `core/magic_numbers.dart`  | generated (M7)                       | const magic numbers and shifts for this square mapping                                                                                                     |
| `core/move.dart`           | rewritten                            | 16-bit `int` move encoding helpers (no class instances in the hot path)                                                                                    |
| `core/zobrist.dart`        | adapted from v9                      | flattened `Int64List` tables, same random structure                                                                                                        |
| `core/board.dart`          | rewritten                            | bitboards + mailbox, make/unmake, null move, repetition stack                                                                                              |
| `core/move_generator.dart` | rewritten                            | legal generation into a caller-supplied `Int32List` buffer                                                                                                 |
| `search/*.dart`            | copied from v9, ported to int moves  | `searcher`, `move_ordering`, `transposition_table`, `evaluator`, `piece_square_tables`, `opening_book(_data)`                                              |
| `v10_engine.dart`          | adapted from `v9_engine.dart`        | `ChessEngine` wrapper                                                                                                                                      |

Outside the folder:

- `lib/engines/engine_registry.dart`: add `'v10': () => V10Engine()`.
- `README.md`: add the v10 line.
- `test/engines/v10_bitboard_test.dart`
- `tool/bench.dart`
- `tool/generate_magics.dart`

---

## Milestone 0: baseline benchmark (before any V10 code)

`tool/bench.dart` imports only the `lib/engines/...` files, with no Flutter imports. It takes an engine id and runs:

- `perft` on startpos depth 5, Kiwipete depth 4 and Position 3 depth 5. It reports nodes, ms and Mnps.
- A fixed-depth search on about 10 middlegame/endgame FENs (depth 6, or depth 5 if slow). It reports nodes, ms, NPS, best move and eval from `EngineMoveResult`.

Run it AOT: `dart compile exe tool/bench.dart -o build/bench && build/bench v9`. JIT numbers are misleading for this kind of code. Record the V9 numbers in the PR description.

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
- **`rays`**: `Uint64List(8*64)`, using the same direction order as V9 (`N,E,S,W,NE,SE,SW,NW` = −8, +1, +8, −1, −7, +9, +7, −9).
- **`between`**: `Uint64List(64*64)`. Squares strictly between `a` and `b` when they're aligned, else 0.
- **`line`**: `Uint64List(64*64)`. The full line through `a` and `b`, edge to edge, when aligned, else 0. This is used for pin restriction.
- **`castleMask`**: `Int32List(64)`, starting at 15. Clear bits as follows:
  - `[56] &= ~4` (a1 → WQ)
  - `[63] &= ~8` (h1 → WK)
  - `[60] &= ~12` (e1)
  - `[0] &= ~1` (a8 → BQ)
  - `[7] &= ~2` (h8 → BK)
  - `[4] &= ~3` (e8)

  The bit order is the same as V9's `castlingRightsAsInt` (8 = WK, 4 = WQ, 2 = BK, 1 = BQ), so the Zobrist castling table indexes the same way.

Use flat typed lists everywhere (`table[a*64+b]`). V9's `List<List<int>>` costs two bounds-checked indirections per lookup.

## Milestone 2: board representation, make/unmake, Zobrist

**`core/move.dart`** uses a 16-bit `int` move, laid out in the Chess Programming Wiki style:

```
bits 0-5  from   bits 6-11  to   bits 12-15 flag
flag: 0 quiet, 1 double pawn push, 2 king castle, 3 queen castle, 4 capture, 5 en passant,
      8 promo N, 9 promo B, 10 promo R, 11 promo Q, 12-15 = promo + capture (N,B,R,Q)
```

- Helpers: `encode(from,to,flag)`, `fromSq(m)`, `toSq(m)`, `flag(m)`, `isCapture(m)` (`flag & 4` for flags 4–5 and 12–15), `isPromotion(m)` (`flag & 8`), `promoType(m)` (maps to `Piece.knight/bishop/rook/queen`), `uci(m)` (reuses `UciMove`, with the promo char from `"nbrq"[flag & 3]`).
- `0` means "no move". `a8a8` quiet is never legal, so it is safe to use as a sentinel. The TT stores the int directly, so V9's `packMove` goes away.

**`core/board.dart`** fields, all plain typed data with no `late`:

```dart
final Uint64List pieceBB = Uint64List(16);   // indexed by piece code (e.g. Piece.whiteKnight)
final Uint64List colourBB = Uint64List(2);   // 0 white, 1 black
int occupied;
final Uint8List squares = Uint8List(64);     // mailbox, kept in sync for O(1) piece-on-square
bool whiteToPlay; int castling; int epSquare /* -1 none */; int halfmove; int zobristKey;
int plyCount;                                // game ply for repetition stack indexing
// Undo stack, preallocated (MAX_GAME_PLY = 2048: 300-move game + search depth + margin)
final Int64List keyStack; final Int32List undoCaptured, undoCastling, undoEp, undoHalfmove;
```

- `Board.fromFEN` uses `FenPosition.parse`. It fills `squares`, `pieceBB`, `colourBB` and `occupied`, computes the key, and pushes the key to the stack.
- Private inline helpers:
  - `_put(piece, sq)`: sets the bit in `pieceBB[piece]` and `colourBB`, sets `squares`, and XORs `zobrist[piece*64+sq]`.
  - `_remove(piece, sq)`: the reverse.
  - `_move(piece, from, to)`: one XOR mask `(1<<from)|(1<<to)` on each bitboard.
- **`makeMove(int m)`**:
  1. Push `captured`, `castling`, `ep` and `halfmove`. Push the key onto `keyStack`.
  2. Read `piece = squares[from]` and `captured = squares[to]`. For en passant the captured pawn is on `to ± 8`.
  3. Remove the captured piece if there is one, then move the piece. On promotion, remove the pawn and put the promoted piece.
  4. Castling: also move the rook (h1→f1, a1→d1, h8→f8, a8→d8 by flag and colour).
  5. Ep: XOR out the old ep key, then set `ep = from ± 8` on a double push, else −1. XOR in the new key. Keep **V9's hashing semantics**: hash the ep square whenever there's a double push, so V9 and V10 keys behave alike.
  6. Castling rights: `castling &= castleMask[from] & castleMask[to]`. If they changed, XOR out the old Zobrist castling key and XOR in the new one.
  7. `halfmove = (pawn move || capture) ? 0 : halfmove + 1`. Flip the side to move and XOR `sideToMove`. Increment `plyCount`.
- **`unmakeMove(int m)`** is the mirror image. Restore scalars from the stacks and **restore `zobristKey` from `keyStack`** rather than un-XORing.
- **`makeNullMove()` / `unmakeNullMove()`**: flip the side, clear ep (with its key), and push the stacks. This is unused in V10 but needed for null-move pruning in V11.
- **`isRepetition()`** replaces the `HashMap`. It scans `keyStack` from `plyCount-2` down to `plyCount-halfmove`, step −2, and returns true on the first match.
  - V9 rule: "seen ≥ 2 times including the current position, at ply > 0", which means one earlier occurrence. That's equivalent to "any earlier match", because positions before an irreversible move can't recur.
  - The search calls `board.isRepetition()` in place of `hashHistory[...] >= 2`.
- **`kingSquare(colour)`**: `lsb(pieceBB[Piece.king | colourCode])`.

**`core/zobrist.dart`**: same generation as V9, flattened:

- `Int64List pieces = (15*64)`
- `castling[16]`
- `ep[65]`
- `side`

Keep `ensureInitialised()` and the "statics per isolate" note. Add `computeFromScratch(Board)` for tests.

## Milestone 3: slider attacks, classical approach first

Use the ray tables and bitscans in `sliders.dart`. For each direction: `attacks |= rays[d][sq]`, then `blockers = rays[d][sq] & occ`, and if `blockers != 0` remove what's behind the first blocker.

- The first blocker is `lsb(blockers)` for directions that increase the index (E, S, SE, SW) and `msb(blockers)` for decreasing ones (N, W, NE, NW).
- Remove behind it with `attacks &= ~rays[d][firstBlocker]`.

This is simple, obviously correct, and a good oracle for the magic version in M7.

## Milestone 4: legal move generator

API (one generator instance per `Searcher`, no per-call allocation):

```dart
int generate(Board b, Int32List out, {bool capturesOnly = false}); // returns count; sets inCheck
bool inCheck;                                   // valid after generate()
bool isInCheck(Board b);                        // attackersTo(kingSq, them, occ) != 0
int attackersTo(Board b, int sq, int occ);      // all pieces of both colours attacking sq
```

Algorithm per call. Here `us`/`them` are colour bitboards, `ksq` is our king square, and `occ` is all occupied squares:

1. **Checkers**:
   ```
   checkers = (knightAttacks[ksq] & theirN)
            | (pawnAttacks[us][ksq] & theirP)
            | (rookAttacks(ksq, occ) & (theirR | theirQ))
            | (bishopAttacks(ksq, occ) & (theirB | theirQ))
   ```
   Set `inCheck = checkers != 0`.
2. **King moves**: for each target in `kingAttacks[ksq] & ~us` (`& them` if captures-only), the move is legal if `attackersTo(target, occ ^ bit(ksq)) & them == 0`. Removing our king from occupancy stops the king "hiding" behind itself on a slider ray. It replaces V9's attack-map special case at `move_generator.dart:297`.
3. **Double check** (`popCount(checkers) > 1`): return after king moves.
4. **Check mask**: −1 (all ones) when not in check, else `between[ksq*64+checker] | checkers`.
5. **Pins**:

   ```
   snipers = (rays orthogonal from ksq on empty board & (theirR | theirQ))
           | (rays diagonal from ksq on empty board & (theirB | theirQ))
   ```

   For each sniper `s`, let `b = between[ksq*64+s] & occ`. If `popCount(b) == 1 && (b & us) != 0`, then `pinned |= b`.

   A pinned piece on `from` may only move to `line[ksq*64+from]`. Pinned knights can never move.

6. **Target mask** = `~us & checkMask`. For captures-only, `them & checkMask`.
7. **Knights, bishops, rooks, queens**: pop-lsb over each piece bitboard. Attacks come from the tables or sliders, and `& target`, and `& line[ksq][from]` if pinned. Emit flag 4 when the target is occupied, else 0.
8. **Pawns**: loop per pawn first (simplest to get right).
   - Pushes: forward 1, and forward 2 from the start rank when both squares are empty. Quiet only, so skip them in captures-only mode.
   - Captures use `pawnAttacks & them`.
   - Apply `& checkMask` and the pin line to every pawn move.
   - From the 7th rank (white rank index 1, i.e. RANK_7; black RANK_2), emit 4 promotions (Q, N, R, B). Promotions with capture use flags 12–15.
   - **Quiet promotions are not generated in captures-only mode.** That matches V9 and the perft "captures" expectations.
   - Set-wise pawn generation using shifts and masks is an optional later optimisation.
9. **En passant** (when `epSquare != -1`): for each of our pawns in `pawnAttacks[them][ep] & ourP`:
   - Check it: if `inCheck`, either the captured pawn square (`ep ± 8`) or `ep` must be in the check mask.
   - Do an exact legality test with the occupancy after the capture: `occ2 = occ ^ bit(from) ^ bit(capSq) | bit(ep)`. Legal only if `rookAttacks(ksq, occ2) & (theirR|theirQ) & ~bit(capSq)` and `bishopAttacks(ksq, occ2) & (theirB|theirQ)` are both 0.
   - This covers the horizontal "two pawns leave the rank" discovered check and the diagonal pins in one test. It replaces V9's `inCheckAfterEnPassant`, which mutates the board.
10. **Castling** (not in check, and not captures-only):
    - White O-O: f1 and g1 (61, 62) empty, and neither attacked.
    - White O-O-O: b1, c1 and d1 (57–59) empty, with c1 and d1 (58, 59) not attacked.
    - Black: same with squares 5, 6 / 1, 2, 3 / 2, 3.
    - Attack tests use `attackersTo(sq, occ) & them`.
    - Rights come from `board.castling` bits.

Keep `perft()` in `V10Engine` structurally identical to V9. That includes the `isInCheck == inCheck` consistency assertion and the captures-only count at depth 1. It recurses using one preallocated `Int32List(256)` per depth.

## Milestone 5: port search, ordering, TT and eval to int moves (behaviour-preserving)

- **`Searcher`**:
  - Preallocate `List<Int32List> moveBuf` and `scoreBuf`, each with `MAX_PLY = 128` entries of 256.
  - Replace `generateLegalMoves(board)` with `count = gen.generate(board, moveBuf[ply])`.
  - Root keeps its own `Int32List` of root moves. "Best move first" reordering becomes a swap-to-front.
  - Repetition becomes `board.isRepetition()`.
  - Qsearch: generate with `capturesOnly` and **read `gen.inCheck`** instead of calling `isInCheck` separately. If in check and `qDepth < qCheckDepthLimit`, regenerate full. Keep V9 semantics for check evasions and mate detection exactly.
  - Time check: compare `_stopwatch.elapsedMicroseconds` to a precomputed int, to avoid allocating a `Duration`.
  - `bestMove` / `pv` become `move.uci(m)` strings.
  - Everything else is unchanged: the same alpha-beta, fail-hard returns, mate scores, `toTT`/`fromTT`, and the root loop.
- **`MoveOrdering`**:
  - Same scores as V9:
    - TT move = 10000.
    - Promotion = `promoType*10` (same piece codes).
    - MVV-LVA `pieceValues[type(captured)]*10 - pieceValues[type(moving)]`, with en passant's victim counted as `Piece.none`, value 1, as V9 does.
  - Read pieces from `board.squares`. Use a `const List<int>` instead of the `Map`.
  - Fill `scoreBuf` once. Then either do an in-place insertion sort or pick the best remaining move lazily in the loop. Both avoid V9's comparator recomputing scores. It's a pure speed change: the order is the same up to ties.
- **`TranspositionTable`**: same structure. `_moves` stores the move int directly, and `packMove` is deleted. Replacement policy is **unchanged** for V10. The fail-low `Move.invalid` overwrite fix waits for V11, so V10 stays a pure speed comparison.
- **`Evaluator`**: rewrite the counting with bitboards but produce **identical** scores:
  - Counts: `popCount(pieceBB[...])`.
  - PST sums: pop-lsb over each piece bitboard, using index `sq` for white and `sq ^ 56` for black, as V9 does.
  - Light/dark bishops: `popCount(bishops & LIGHT_SQUARES)`.
  - King squares: `lsb`.
  - The material, phase, insufficient-material, mop-up and tapered-PST logic is copied verbatim.
  - No per-call list allocation: use fields or a reused `Int32List`.

## Milestone 6: engine wrapper, registry, docs

- **`V10Engine`**: a copy of `V9Engine`. Parse `uciMoves` by generating legal moves into a buffer and matching `move.uci(m)`. Keep the opening book logic. `displayName: 'V10 - Bitboards'`.
- Add `'v10'` to `EngineRegistry`. That makes it the `latestId` used by the app, and puts it under the perft and mate tests.
- Add the README line `**v10** - Bitboard board representation and move generation (+N ELO)`. Fill N in after the match.

## Milestone 7: magic bitboards (measured, optional but expected to help)

- **`tool/generate_magics.dart`**: for each square, build relevance masks (rays excluding edges), then do a random sparse-number search with a fixed seed until there are no destructive collisions. It writes `lib/engines/v10/core/magic_numbers.dart` with const `rookMagics`, `bishopMagics` and per-square bit counts. **Generate them for this a8 = 0 mapping**: published magics assume a1 = 0.
- **`sliders.dart`**: `rookAttacks(sq, occ) = rookTable[rookOffset[sq] + (((occ & rookMask[sq]) * rookMagic[sq]) >>> rookShift[sq])]`. The tables are one `Uint64List` each (about 102,400 rook and 5,248 bishop entries, under 1 MB). They're filled at first use from the classical routine, which takes a few ms per isolate.
- Keep the classical implementation in `sliders.dart` as `rookAttacksSlow`. It's the test oracle.
- Benchmark classical vs magic, and keep magic only if it's faster in AOT. Expect around 1.3–2×.

## Milestone 8: validate strength

- Run `tool/bench.dart v10` against the V9 numbers and check the NPS targets.
- Run a match in the match manager: V10 vs V9, 100 ms, 1000+ games, with the existing opening book. Record the Elo in the README.

---

## Tests: `test/engines/v10_bitboard_test.dart`

This file can import both v9 and v10, because test files aren't covered by snapshot purity. **V9 is a perfect oracle**: its generator already passes perft.

1. **BitOps**: `popCount`, `lsb` and `msb` against naive loops on 10k random 64-bit values. Include ones with bit 63 set, 0 for popcount, and single-bit values.
2. **Leaper tables**: for every square, the `knightAttacks`/`kingAttacks`/`pawnAttacks` bitboards equal the V9 `PrecomputeData` lists converted to bitboards.
3. **Sliders**: classical rook/bishop attacks vs a naive square-by-square ray walk on 10k random occupancies per square. After M7, magic vs classical too.
4. **`between` / `line`**: spot checks, for example a8–h1 diagonal, e1–e8 file, a1–c2 (not aligned → 0).
5. **Board invariants fuzz**: random playouts of 200 plies from each perft FEN, repeated. At every node check:
   - `zobristKey == Zobrist.computeFromScratch(board)`
   - `pieceBB`/`colourBB`/`occupied` agree with `squares`
   - after `unmakeMove`, every field equals the snapshot taken before `makeMove`

   Include null-move make/unmake.

6. **Move generation oracle**: on all positions visited in (5), about 50k:
   - the set of UCI strings from V10 `generate` equals V9 `generateLegalMoves`, both full and captures-only
   - `gen.inCheck` equals V9's `inCheck`

   On failure, print the FEN, the missing moves and the extra moves. That pinpoints a bug far faster than perft numbers.

7. **Targeted edge-case FENs** (also run through the oracle):
   - ep capture exposing a horizontal check: `8/8/8/KPp4r/8/8/8/7k w - c6 0 1`
   - ep that evades a check from the double-pushed pawn
   - castling through or out of check
   - castling after the rook is captured on its home square
   - promotion with and without capture, including in captures-only mode
   - a pinned pawn that can only capture its pinner
8. **Eval oracle**: V10 `Evaluator.evaluate` equals V9 `Evaluator.evaluate` for every position in (5).
9. **Repetition**: play `Nf3 Nf6 Ng1 Ng8` from the start and check `isRepetition()` matches V9's `hashHistory` rule at every ply.
10. **Automatic via the registry**:
    - `perft_all_versions_test.dart` (all 6 positions, including Position 5/6 depth 5)
    - `mate_all_versions_test.dart`
    - `snapshot_purity_test.dart`
    - `adapter_test.dart`

Run with `flutter test test/engines/v10_bitboard_test.dart`, then the full `flutter test`.

## Order of work, with checkpoints

| Step                     | Done when                                                                               | Rough size |
| ------------------------ | --------------------------------------------------------------------------------------- | ---------- |
| M0 bench                 | V9 numbers recorded                                                                     | ½ day      |
| M1 bitops + tables       | tests 1–2, 4 green                                                                      | ½ day      |
| M2 board + zobrist       | test 5 green (driven by a temporary move source: decode V9's generated moves into ints) | 1 day      |
| M3 sliders               | test 3 green                                                                            | ½ day      |
| M4 generator             | tests 6–7 green, then perft green                                                       | 1–2 days   |
| M5 search/eval port      | test 8, 9 green; mate tests green; bench shows the NPS gain                             | 1 day      |
| M6 wrapper/registry/docs | full `flutter test` green                                                               | ½ day      |
| M7 magics                | slider oracle green; bench shows the gain                                               | ½–1 day    |
| M8 match                 | Elo recorded in README                                                                  | match time |

## Risks and how they're handled

- **Shift and sign bugs** (`>>` vs `>>>`, file wrap on diagonal shifts): BitOps and table tests, plus the generator oracle.
- **Orientation confusion (a8 = 0)**: constants are defined once in `bitboard.dart`, plus a `toAscii()` debug printer. Tests compare against V9, which uses the same mapping.
- **En passant and castling edge cases**: targeted FENs and the oracle. Perft Position 3 covers the ep horizontal pin, and Kiwipete covers castling.
- **Behaviour drift that would muddy the Elo comparison**: eval oracle and identical ordering scores. TT, qsearch and root logic are copied verbatim. Only move tie-order and hash-collision behaviour can differ.
- **Web builds**: `Uint64List` and 64-bit literals are unsupported, but the engine already needs isolates. Document this in the README.

## After V10 (unchanged from the review, now on the int-move API)

- V11, search: null move (uses `makeNullMove`), killers + history, PVS, check extension, TT fail-low move fix, aspiration windows.
- V12: LMR + futility/RFP.
- V13 eval, made cheap by bitboards: PeSTO, passed/isolated/doubled pawns via file masks, mobility via `popCount(attacks)`, king safety, SEE in qsearch.
- Later: Texel tuning.
