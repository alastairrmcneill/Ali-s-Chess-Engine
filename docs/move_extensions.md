# v10 — Moves as a 16-bit Extension Type: Build-It-Yourself Plan

## Background reading (do this first)

1. **Bit packing.** Make sure you're comfortable with these operators on `int`: `|` (OR), `&` (AND),
   `<<` and `>>` (shifts). Practise in DartPad: put the number 5 into bits 6–11 of an int, then get
   it back out.
2. **Masks.** What decimal value has its lowest 6 bits all set? Write it in hex too. You'll use this
   number a lot.
3. **Extension types.** Read the Dart language docs page "Extension types". Answer for yourself:
   - What is the _representation type_, and what is it at runtime?
   - What can an extension type declare: getters, methods, constructors, static members?
   - What _can't_ it do that a class can? Think about `toString`, `is` checks and fields.
   - Which language version introduced them?

<details><summary>Hint: check your answers</summary>

- At runtime an extension type _is_ its representation type. The wrapper disappears when the code
  is compiled.
- It can have getters, methods, constructors and static members, but no instance fields beyond the
  representation.
- It can't override `toString`/`==`/`hashCode`, and `x is Move` can't tell a `Move` from an `int`.
- Dart 3.3.
</details>

---

## Phase 0 — Design the encoding (on paper)

Before you write any code, design how a move fits into 16 bits. Write your answers into the PR
description later. They become the documentation.

1. How many bits do you need for a square index 0–63?
2. A move needs a from-square and a to-square. How many bits is that? How many are left in 16?
3. List every _kind_ of move the current `Move` class can describe. Look at its boolean fields
   and the `promotion` int. Can a single move ever be two kinds at once? Is a capture a "kind",
   or can the board tell you that?
4. Give each kind a small number (a "flag"). Do they fit in the bits that are left?
5. **Try to pick the promotion flag numbers** so that turning a flag back into the old
   `promotion` value (1 = queen, 2 = knight, 3 = rook, 4 = bishop) is a single subtraction.
   That way `promotingPiece()` and the UCI string code keep working unchanged.
6. Which packed value can never be a legal move? Use it to mean "no move". Check what the current
   `Move.invalid` and `TranspositionTable.packMove(Move.invalid)` produce. Does your choice match?

<details><summary>Hint: a common layout</summary>

From in bits 0–5, to in bits 6–11, flag in bits 12–15. Flags: normal, en passant, castling, pawn
two forward, then the four promotions in queen/knight/rook/bishop order, so `promotion = flag - 3`.
`0` is a8→a8, which is never legal.

</details>

**Done when…**

- [ ] You have a written table of bit positions and flag values.
- [ ] You can encode and decode a move like e7e8=N by hand, on paper.

---

## Phase 1 — Snapshot v9 as v10

A new version that behaves exactly like v9. No logic changes.

1. Copy `lib/engines/v9/` to `lib/engines/v10/`.
2. Fix every import inside v10 so it points at v10, not v9. (Search for it. Missing one is easy.)
3. Rename the engine file and class, and give it a new `id` and `displayName`. Check for any
   error messages that mention "v9".
4. Register the new engine in `lib/engines/engine_registry.dart`.
5. Look at how `perft_all_versions_test.dart` and `mate_all_versions_test.dart` find engines.
   Will they pick up v10 automatically?

**Done when…**

- [ ] A search for `engines/v9` inside `lib/engines/v10` finds nothing.
- [ ] `test/engines/snapshot_purity_test.dart` passes. Read it first so you know what it enforces.
- [ ] All of `test/engines/` passes, with v10 included.
- [ ] Committed on its own: "v10: snapshot of v9". A clean baseline commit makes later diffs easy to
      review.

---

## Phase 2 — Allow extension types

Your `pubspec.yaml` currently allows Dart 3.1. Work out what needs to change so extension types are
allowed. Check the `sdks:` section of `pubspec.lock` to confirm the change is safe for the SDK you
actually use.

**Done when…**

- [ ] `flutter pub get` and `flutter analyze` both succeed.

---

## Phase 3 — Build the `Move` extension type

Rewrite `lib/engines/v10/core/move.dart`. Before you start, list every member the current class
has, then search `lib/engines/v10` to see which of them are actually used and where. That list is
your spec: anything used must still work afterwards.

### 3a. The type itself

- Declare an extension type over `int` named `Move`. Give its primary constructor a name (e.g.
  `raw`), so that the plain `Move(...)` name is free for step 3c.
- Add `static const` values for each flag from Phase 0, and a `static const` for "no move".

### 3b. Decoding: getters

Add a getter for each piece of information you can read from a move, **using the same names as
the old class fields**. Then the board and move generator won't need to change. You'll need:

- the from-square and to-square (shift, then mask)
- the raw flag
- one `bool` getter per special move kind
- `promotion`, returning the old 1–4 numbering, or 0
- a way to ask "is this the no-move value?"

Then bring across `promotingPiece()`, `uci` and `toChessNotation()`. Do they need any changes, given
your getters keep their old names?

### 3c. Encoding: constructors

You want two:

1. **A fast positional constructor** taking `(from, to, [flag])`. This is what a future, faster
   move generator will use.
2. **A compatibility constructor** with exactly the same named parameters as the old class
   (`startingSquare:`, `targetSquare:`, `enPassantCapture:`, …). It works out the right flag from
   the booleans and the promotion number. This is what lets `move_generator.dart` compile untouched.

Constructors on an extension type must initialise the representation value in an initializer list.
Work out how to do that from the language docs.

<details><summary>Hint: if the compatibility constructor won't compile</summary>

If the analyzer rejects an unnamed constructor alongside the named primary one, turn the
compatibility version into a `static Move create({...})` method instead. Then do a search-and-replace
of `Move(` to `Move.create(` in the move generator only.

</details>

### 3d. Things to delete

- `isSameAs`: what replaces it, now that a move is an int?
- `toString`: why can't you keep it? What will `print(move)` show now, and what should you log instead?
- `Move.invalid`: replace it with your no-move constant, and update every caller.

### 3e. Write the tests _before_ moving on

Create `test/engines/v10_move_test.dart`. Design tests that would catch any mistake in your
encoding:

- **Round trip.** Encode and then decode _every_ combination of from, to and flag. How many cases is
  that? Is it small enough to loop over all of them?
- **Compatibility constructor.** One test per move kind, checking every getter: normal, en passant,
  castling, double push and each of the four promotions.
- **UCI strings.** A normal move (e.g. e2e4) and each promotion letter. You'll need the square
  indices: remember a8 is 0 in this engine.
- **No move.** The constant decodes as "no move", and no legal move from the start position does.
- **Equality.** Two separately built identical moves are `==`. Changing only the flag makes them
  different.

**Done when…**

- [ ] `flutter analyze` is clean for `lib/engines/v10`. If `board.dart` or `move_generator.dart`
      needed edits, ask yourself why: a getter or constructor probably doesn't match the old API.
- [ ] Your move tests pass.
- [ ] No `isSameAs` or `Move.invalid` remains in v10.

---

## Phase 4 — Transposition table

Open `lib/engines/v10/search/transposition_table.dart` and read `packMove`.

1. Compare `packMove` with your encoding. What information does it **throw away**? Why didn't
   that matter in v9?
2. Remove `packMove`. Store the move's own value instead.
3. What is the smallest typed-data list that can hold your move values? Switch the moves array to
   it. How much memory does that save at the default table size?
4. Change the signatures so `store` takes a `Move` and `moveAt` returns a `Move`, not an `int`.
   Keeping these typed is what stops you storing a depth or a score in the move slot by accident.

**Done when…**

- [ ] `packMove` is gone and no plain `int` crosses the TT's API for a move.

---

## Phase 5 — Move ordering

Open `lib/engines/v10/search/move_ordering.dart`.

1. Change the `ttMove` parameter type from `int` to `Move`. What should its default value be?
2. Simplify the "is this the TT move?" check now that both sides are the same type.
3. Remove any import that's no longer needed.

⚠️ **Don't fix the double-scoring comparator yet**, even though you know how. Ask yourself: why
would fixing it now break the Phase 8 test? (Think about moves with equal scores.)

---

## Phase 6 — Searcher

Open `lib/engines/v10/search/searcher.dart` and let the analyzer guide you. Fix each error it
reports. While you're there, think about:

1. Where does the searcher hold the TT move as an `int`? Change it to `Move`.
2. Where does it fall back to `Move.invalid`?
3. Find the line that removes the best move from the root move list with `!=`. In v9, did that
   compare _identity_ or _values_? What does it compare now? Does the result change? Why not?
4. `Move?` (nullable) appears in several places. Is a nullable small int expensive in Dart? Look up
   how the Dart VM represents small integers ("Smi"). Decide whether to keep `Move?` or use your
   no-move constant, and be consistent.

---

## Phase 7 — Adapter and perft

Read `lib/engines/v10/v10_engine.dart` top to bottom. It converts moves to UCI strings and runs
perft. Does anything need to change? Explain to yourself why or why not.

**Done when…**

- [ ] `flutter analyze` is clean.
- [ ] All of `test/engines/` passes, and perft gives exactly the expected counts for v10. Pay
      special attention to the promotion and castling positions (Kiwipete, position 4). If your
      flags are wrong, that's where it shows.

---

## Phase 8 — Prove v10 searches exactly like v9

This is your strongest test. Create `test/engines/v9_v10_packed_move_equivalence_test.dart`, using
`v7_v8_transposition_comparison_test.dart` as your model.

1. Reuse its fixed-depth position list. Why must this test use a **fixed depth** and not a time
   limit?
2. For each position, run both engines and assert they produce the same move, eval, **node count**
   and transposition count.
3. Print a table of v9 time vs v10 time. Why should you _print_ the timing rather than _assert_ on
   it?

Before you run it, write down **why** the node counts should be identical. Your answer should
cover:

- move generation order
- the sort comparator
- the TT move check
- the no-move value

If counts differ, debug in this order:

1. A promotion flag off by one.
2. A TT move still compared or stored as a raw int somewhere.
3. A missed `Move.invalid`.
4. The compatibility constructor picking the wrong flag when several booleans are passed.

**Done when…**

- [ ] Every position matches exactly.
- [ ] v10 is faster in total, with the numbers recorded.

---

## Phase 9 — Measure and document

1. **Perft speed.** Time perft depth 5 from the start position for v9 and v10. Work out nodes per
   second for each. Perft is mostly move generation plus make/unmake. Why does that make it the
   best place to see this change?
2. **Match.** Play v10 against v9 with `bin/match.dart`. Before you look at the result, predict it:
   the search is identical, so where could any Elo gain come from? How big do you expect it to be?
3. **README.** Add the v10 line in the same style as the others.

**Done when…**

- [ ] Perft nps, the equivalence table and the match result are in the PR description.
- [ ] README updated.

---

## Self-review checklist

Before opening the PR, check each of these against your own code:

- [ ] Flags 4–7 decode to the right promotion piece, including capture-promotions.
- [ ] Every function that takes or returns a move uses `Move`, not `int`. Only the TT array
      touches the raw value.
- [ ] No `is Move` checks anywhere. Why would they be wrong?
- [ ] No log or error message prints a move with `"$move"`.
- [ ] `GameState` is unchanged. Confirm it never stored a move.
- [ ] You can explain why 16-bit moves are safe on the web build, while 64-bit bitboards wouldn't be.

---

## What comes next (separate versions)

Each of these changes search behaviour, so node counts will no longer match v9. Judge them by
time-to-depth, nodes per second and match results. Write a plan like this one for each before
starting.

1. **Score each move once** instead of inside the sort comparator. Compare a scored insertion
   sort with pick-best-as-you-go.
2. **Per-ply move buffers.** Stop building a new list on every call to the move generator.
3. **Killer moves and history.** Use `firstMoveCutoffs / betaCutoffs` to measure ordering quality.
4. **Try the TT move before generating moves.** What new check does this need, and why?
5. **Bitboards.**
