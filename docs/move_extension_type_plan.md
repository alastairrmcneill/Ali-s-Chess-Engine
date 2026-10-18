# v10 — Moves as a 16-bit Extension Type: Implementation Plan

A step-by-step plan for replacing the engine's `Move` class with a Dart **extension type** over a
16-bit `int`. This is the first step towards a faster move generator: every generated move stops
being a heap object, the transposition table stores complete moves, and move ordering stops
re-packing moves inside the sort comparator.

The aim of this version is a **pure representation change**. v10 must search exactly the same
tree as v9: same moves generated in the same order, same best move, same eval, **same node count**
at a fixed depth. That gives us a very strong test, and any difference is a bug in the encoding.
Speed-ups that change search behaviour (score-once ordering, killers, move buffers) come in later
versions.

Do the phases in order. Each one ends with a **Done when…** checklist.

---

## 0. Decisions

| Topic                | Decision                                                                                                                                         |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Where                | New snapshot **`lib/engines/v10/`**, copied from v9. v9 and earlier stay frozen. `chess_core`, the referee and the UI keep their own `Move` class |
| Representation       | `extension type const Move.raw(int value)`: a compile-time type, a plain `int` at runtime (no allocation, no wrapper)                            |
| Why not plain `int`  | Same speed, but the compiler stops a square, score or depth being passed where a move is expected, and the bit layout lives in one file          |
| Encoding             | 16 bits: `from` bits 0–5, `to` bits 6–11, `flag` bits 12–15                                                                                       |
| "No move"            | `Move.none == Move.raw(0)` (a8→a8, never legal). Replaces `Move.invalid`                                                                         |
| Call-site compatibility | Getter names stay the same (`startingSquare`, `targetSquare`, `promotion`, `castling`, …) and a named-argument constructor matches the old one, so the board and move generator compile unchanged |
| Behaviour            | **Identical to v9.** No ordering, search or eval changes in this version                                                                          |
| SDK                  | Raise `environment.sdk` to `>=3.3.0 <4.0.0` (extension types need language 3.3; the lockfile already resolves Dart 3.11)                         |

### Flag values

| Flag | Meaning                                    | Old fields it replaces       |
| ---- | ------------------------------------------ | ---------------------------- |
| 0    | Normal move (captures included)            | —                            |
| 1    | En passant capture                         | `enPassantCapture: true`     |
| 2    | Castling                                   | `castling: true`             |
| 3    | Pawn two forward                           | `pawnTwoForward: true`       |
| 4    | Promote to queen                           | `promotion: 1`               |
| 5    | Promote to knight                          | `promotion: 2`               |
| 6    | Promote to rook                            | `promotion: 3`               |
| 7    | Promote to bishop                          | `promotion: 4`               |

`promotion == flag - 3` for flags 4–7, so the existing numbering (and `" qnrb"[promotion]` in
`uci`) keeps working.

---

## Phase 1 — Snapshot v9 as v10

No behaviour change. Just a new version that is byte-for-byte v9 apart from names.

1. Copy the folder: `cp -r lib/engines/v9 lib/engines/v10`.
2. In every file under `lib/engines/v10/`, change `package:ace/engines/v9/` to
   `package:ace/engines/v10/`.
3. Rename `v9_engine.dart` to `v10_engine.dart`, and `V9Engine` to `V10Engine`.
   - `id => 'v10'`
   - `displayName => 'V10 - Packed moves'`
   - The error message `'v9 move generator does not consider …'` becomes `v10`.
4. Register it in `lib/engines/engine_registry.dart`:
   ```dart
   import 'package:ace/engines/v10/v10_engine.dart';
   ...
   'v10': () => V10Engine(),
   ```

**Done when…**

- [ ] `grep -rn "engines/v9" lib/engines/v10` returns nothing.
- [ ] `flutter test test/engines/snapshot_purity_test.dart` passes. It checks that v10 only imports
      v10, `chess_core/notation` and the engine interface.
- [ ] `flutter test test/engines/` passes. `perft_all_versions_test` and `mate_all_versions_test`
      pick up v10 through the registry.
- [ ] Commit: *"v10: snapshot of v9"*.

---

## Phase 2 — Raise the SDK constraint

In `pubspec.yaml`:

```yaml
environment:
  sdk: ">=3.3.0 <4.0.0"
```

**Done when…**

- [ ] `flutter pub get` succeeds and `flutter analyze` shows no new issues.

---

## Phase 3 — The new `Move` type

Replace `lib/engines/v10/core/move.dart` entirely:

```dart
import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/engines/v10/core/piece.dart';

/// A move packed into 16 bits: from (bits 0-5), to (6-11), flag (12-15).
/// At runtime this is a plain int, so creating, storing and comparing moves allocates nothing.
extension type const Move.raw(int value) {
  static const int flagNone = 0;
  static const int flagEnPassant = 1;
  static const int flagCastling = 2;
  static const int flagPawnTwoForward = 3;
  static const int flagPromoteQueen = 4; // 5 knight, 6 rook, 7 bishop

  /// a8 -> a8 can never be a legal move, so 0 means "no move".
  static const Move none = Move.raw(0);

  /// Positional constructor for hot paths.
  Move.encode(int from, int to, [int flag = flagNone]) : value = from | (to << 6) | (flag << 12);

  /// Same named arguments as the old class, so existing call sites compile unchanged.
  Move({
    required int startingSquare,
    required int targetSquare,
    bool enPassantCapture = false,
    bool pawnTwoForward = false,
    int promotion = 0,
    bool castling = false,
  }) : value = startingSquare |
            (targetSquare << 6) |
            ((promotion != 0
                    ? promotion + 3
                    : enPassantCapture
                        ? flagEnPassant
                        : castling
                            ? flagCastling
                            : pawnTwoForward
                                ? flagPawnTwoForward
                                : flagNone) <<
                12);

  int get startingSquare => value & 0x3F;
  int get targetSquare => (value >> 6) & 0x3F;
  int get flag => value >> 12;

  bool get isNone => value == 0;
  bool get enPassantCapture => flag == flagEnPassant;
  bool get castling => flag == flagCastling;
  bool get pawnTwoForward => flag == flagPawnTwoForward;
  bool get isPromotion => flag >= flagPromoteQueen;

  /// 1 queen, 2 knight, 3 rook, 4 bishop, 0 none (same numbering as v9).
  int get promotion => isPromotion ? flag - 3 : 0;

  int promotingPiece() {
    switch (promotion) {
      case 1:
        return Piece.queen;
      case 2:
        return Piece.knight;
      case 3:
        return Piece.rook;
      case 4:
        return Piece.bishop;
      default:
        return Piece.none;
    }
  }

  String get uci => UciMove(
        from: startingSquare,
        to: targetSquare,
        promotion: promotion == 0 ? null : " qnrb"[promotion],
      ).toString();

  String toChessNotation() {
    String files = "abcdefgh";

    int startingFile = BoardHelper.getFileFromIndex(startingSquare);
    int startingRank = 8 - BoardHelper.getRankFromIndex(startingSquare);
    int targetFile = BoardHelper.getFileFromIndex(targetSquare);
    int targetRank = 8 - BoardHelper.getRankFromIndex(targetSquare);

    return "${files[startingFile]}$startingRank${files[targetFile]}$targetRank";
  }
}
```

What was removed, and what replaces it:

| Old                  | New                                                                         |
| -------------------- | --------------------------------------------------------------------------- |
| `Move.invalid`       | `Move.none`                                                                 |
| `isSameAs(other)`    | `==` (compares the ints, so it is true exactly when every field matches)   |
| `toString()` override | Not possible on an extension type. `print(move)` shows a number, so log `move.uci` |

`board.dart` and `move_generator.dart` should compile **without edits**. They only use the
named constructor and the getters above.

### Tests: `test/engines/v10_move_test.dart`

1. **Round trip, exhaustive.** For every `from` 0–63, every `to` 0–63 and every flag 0–7, build
   `Move.encode(from, to, flag)` and check `startingSquare`, `targetSquare` and `flag` come back
   unchanged. That is 32,768 cases and runs in milliseconds.
2. **Named constructor matches the old fields.** One case each:
   - normal
   - en passant
   - castling
   - pawn two forward
   - each of the 4 promotions

   Check `enPassantCapture`, `castling`, `pawnTwoForward`, `promotion` and `promotingPiece()`.
3. **UCI strings.**
   - `Move(startingSquare: 52, targetSquare: 36).uci == 'e2e4'`
   - a promotion gives `'e7e8q'`, `'e7e8n'`, …
4. **None.** `Move.none.isNone`, `Move.none.value == 0`, and no legal move from the start position
   `isNone`.
5. **Equality.** Two moves built separately with the same fields are `==`; a different flag makes
   them `!=`.

**Done when…**

- [ ] `flutter analyze` is clean for `lib/engines/v10`.
- [ ] `v10_move_test.dart` passes.
- [ ] `grep -rn "isSameAs\|Move.invalid" lib/engines/v10` returns nothing.

---

## Phase 4 — Transposition table

File: `lib/engines/v10/search/transposition_table.dart`

1. Delete `packMove`.
2. `final Int32List _moves` becomes `final Uint16List _moves`, created with `Uint16List(1 << sizePower)`.
3. `int moveAt(int slot) => _moves[slot];` becomes `Move moveAt(int slot) => Move.raw(_moves[slot]);`
4. In `store`: `_moves[i] = packMove(move);` becomes `_moves[i] = move.value;`

The stored move now keeps its flags, so a TT move is a complete, playable move. Nothing uses that
yet. It's what makes "try the TT move before generating moves" possible later.

**Done when…**

- [ ] `grep -rn "packMove" lib/engines/v10` returns nothing.

---

## Phase 5 — Move ordering

File: `lib/engines/v10/search/move_ordering.dart`

1. Change the parameter in both methods: `{int ttMove = 0}` / `int ttMove` become
   `{Move ttMove = Move.none}` / `Move ttMove`.
2. `if (TranspositionTable.packMove(move) == ttMove) return 10000;` becomes
   `if (move == ttMove) return 10000;`
3. Remove the now-unused `transposition_table.dart` import.

**Leave the comparator exactly as it is**, double scoring included. Fixing that changes the order
of equally scored moves and would break the node-count equivalence in Phase 8. It is the first
item under *Next steps*.

---

## Phase 6 — Searcher

File: `lib/engines/v10/search/searcher.dart`

| Line (v9)                                              | Change to                                         |
| ------------------------------------------------------ | ------------------------------------------------- |
| `int ttMove = 0;`                                      | `Move ttMove = Move.none;`                        |
| `ttMove = tt.moveAt(slot);`                            | unchanged (now returns `Move`)                    |
| `bestMoveHere ?? Move.invalid`                         | `bestMoveHere ?? Move.none`                       |
| `orderedMoves.where((m) => m != iterationBestMove)`   | unchanged. It now compares by value, which gives the same result since a list never holds the same move twice |

`Move?` stays nullable in `bestMove`, `iterationBestMove`, `bestMoveHere` and `getBestMove`'s
return type. Small ints are stored directly by the Dart VM, so a nullable `Move` costs no
allocation. Switching to a `Move.none` sentinel everywhere is optional tidying, not needed here.

---

## Phase 7 — Adapter

File: `lib/engines/v10/v10_engine.dart`

There's nothing to change. `moveToUci` uses `move.uci`, `getMove` matches candidates by their UCI
string, and perft only counts moves. Read it through once to confirm it compiles.

**Done when…**

- [ ] `flutter analyze` is clean.
- [ ] `flutter test test/engines/` passes. Perft must give exactly the expected counts, including
      the Kiwipete and position 4 promotion and castling cases.

---

## Phase 8 — Prove v10 searches exactly like v9

New file: `test/engines/v9_v10_packed_move_equivalence_test.dart`. Copy the structure of
`v7_v8_transposition_comparison_test.dart`: same `_Position` list, same `_run` helper, fixed
depth, no time limit.

For every position, assert:

```dart
expect(v10.move, v9.move, reason: p.name);
expect(v10.eval, v9.eval, reason: p.name);
expect(v10.nodes, v9.nodes, reason: p.name);   // the strong one
expect(v10.transpositions, v9.transpositions, reason: p.name);
```

Print a table with v9 ms, v10 ms and the speed-up per position. Timing is reported, not asserted,
because it is too noisy for CI.

Why the node counts must match exactly:

- Move generation is untouched, so the moves come out in the same order.
- The ordering comparator is unchanged and `List.sort` is deterministic for the same input.
- A TT move matches the same move as before. Flags are fully determined by from/to in a given
  position, so adding them to the stored move changes no comparison result.
- `Move.none` packs to 0, as `Move.invalid` did.

If a count differs, the encoding or one of the changed call sites is wrong. The usual suspects:

- a promotion flag off by one
- `ttMove` still compared as a raw int somewhere
- a missed `Move.invalid`

**Done when…**

- [ ] The equivalence test passes on every position.
- [ ] v10 is faster in total. Record the numbers.

---

## Phase 9 — Benchmark, match, document

1. **Perft speed.** Time `V10Engine().perft(startpos, 5)` against v9 and note nodes per second.
   Most of this version's gain should show up here, since perft is almost pure generation plus
   make/unmake.
2. **Match.** Run `dart run bin/match.dart` v10 vs v9 at your usual `--movetime`. With identical
   search, any Elo gain comes only from reaching deeper in the same time, so expect a small
   positive result, not a big one.
3. **README.** Add the line:
   `**v10** - Moves packed into 16-bit ints (+N ELO).`

**Done when…**

- [ ] Perft nps and the match result are recorded in the PR description.
- [ ] README updated.

---

## Pitfalls checklist

- [ ] **Promotion mapping.** Flags 4–7 are queen, knight, rook, bishop, matching `promotion` 1–4. A
      capture that promotes is still flag 4–7. The board tells you a piece was taken.
- [ ] **Raw ints leaking in.** Keep `Move` in every signature (`store(..., Move move, ...)`,
      `moveAt` returns `Move`). Only `move_list`-style buffers and the TT array should touch
      `.value` / `Move.raw`.
- [ ] **No `is Move` checks.** At runtime a `Move` is an `int`, so a type test can't tell them apart.
- [ ] **Logging.** `"$move"` prints a number. Use `move.uci`.
- [ ] **Web.** 16-bit values are safe under dart2js. Only 64-bit bitboards have the JS integer problem.
- [ ] **`GameState` is unchanged.** It never stored the move, and `unMakeMove` gets the move as a
      parameter.

---

## Next steps (separate versions, each measured on its own)

These change search behaviour, so node counts will no longer match v9. Measure them with
time-to-depth, nodes per second and matches.

1. **Score each move once.** Replace the sort comparator with a scored insertion sort, or with
   pick-best-as-you-go using a per-ply score buffer. Also change `pieceValues` from a `Map` to a
   `const List`.
2. **Per-ply move buffers.** A `MoveList` with a `Uint16List(218)` plus a count, one per ply. The
   generator writes into it instead of building a new `List<Move>` on every call.
3. **Better ordering.** Killer moves and a history table. Track
   `firstMoveCutoffs / betaCutoffs` in `SearchStats` and aim for 90%+.
4. **TT move first.** Try it before generating any moves. This needs a legality check because of
   hash collisions.
5. **Bitboards.** Covered in its own plan.
