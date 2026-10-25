# Move buffers (M5 step 5: remove per-node allocation)

## The problem

Every call to `generate()` currently starts with `moves = []`, which allocates a new `List<Move>` on the heap. Search calls the generator at every node, so that is millions of allocations per search. Each list grows, may be copied as it grows, and is then garbage collected, which costs time and can cause GC pauses.

## The change

Allocate the memory once at startup. The generator writes moves into a buffer the caller supplies and returns how many it wrote.

```dart
// Before
List<Move> generate(Board b, {bool capturesOnly = false})

// After
int generate(Board b, Int32List out, {bool capturesOnly = false}) // returns count
```

Inside the generator, replace `moves.add(Move.encode(...))` with:

```dart
out[n++] = Move.encode(from, to).value;
```

`n` is a local counter that is returned at the end. `Move` is an extension type over `int`, so storing `.value` in an `Int32List` loses nothing (a move is 16 bits). Read a move back with `Move.raw(out[i])`.

## Why one buffer per ply

Search is recursive. A node at ply 3 loops over its moves, calls a child at ply 4, then carries on with its own loop. If parent and child shared one buffer, the child would overwrite the parent's moves. So each ply gets its own buffer:

```dart
static const maxPly = 128;
final List<Int32List> moveBuf  = List.generate(maxPly, (_) => Int32List(256));
final List<Int32List> scoreBuf = List.generate(maxPly, (_) => Int32List(256));
```

- 128 plies of depth.
- 256 slots per ply. A chess position has at most about 218 legal moves, so 256 is safe.
- `scoreBuf` holds the move-ordering score for the move at the same index.

Usage in search:

```dart
int search(int depth, int ply, ...) {
  final moves = moveBuf[ply];
  final count = gen.generate(board, moves);
  for (int i = 0; i < count; i++) {
    final move = Move.raw(moves[i]);
    ...
  }
}
```

The root keeps its own buffer. Iterative deepening reorders the root moves between iterations and keeps them for the whole search, so the root must not share space with a normal ply-0 node.

## Swap to front

With a `List`, "put the best move first" meant remove-then-insert-at-0, which shifts every element and may allocate. On a fixed array it is one swap:

```dart
void swapToFront(Int32List moves, int bestIdx) {
  final tmp = moves[0];
  moves[0] = moves[bestIdx];
  moves[bestIdx] = tmp;
}
```

The order of the remaining moves does not matter because they are sorted by score anyway.

## MoveOrdering signature

`MoveOrdering` can no longer take a `List<Move>` and return a new sorted list. It sorts in place. `count` matters because the buffer has 256 slots but only `count` are valid:

```dart
void orderMoves(Board b, Int32List moves, int count, Int32List scores, ...)
```

It fills `scores[0..count)` and sorts `moves` and `scores` together up to `count`. A selection or insertion sort is fine for about 30 moves.

## Gotchas

- Never read past `count`. Slots beyond it hold stale moves from earlier nodes.
- Anything that iterates `generate(board)` as a list needs updating: `v12_engine.dart` (`getMove` legality check and `_perft`), the Generator test tab and the oracle/perft tests. Perft can use per-depth buffers, `List.generate(depth + 1, (_) => Int32List(256))`. For tests and the tab, write a small helper that makes a buffer and returns `[for (i < count) Move.raw(buf[i])]`.

## Why this wasn't an issue in v11 and earlier

It was always a cost. It was hidden because the old generator was far slower per node, so the list allocation was a small share of each call.

- The mailbox generator walked rays square by square, computed pins and checks by scanning, and used per-call collections such as `checkedRayIndexes.contains(...)`.
- Illustrative numbers: if the generator took about 1000 units and the list allocation about 30, allocation was about 3% of the call and not worth fixing.
- Bitboards make the generator several times faster through table lookups, `lsb` and mask arithmetic. Allocation does not get faster. With the same 30 units against a generator now at roughly 120, allocation is about 20% of the call. Same cost, bigger share (Amdahl's law: when the main bottleneck shrinks, the next one appears).
- Search features added over the versions (quiescence search, check evasions in qsearch, the transposition table, move ordering) call the generator more often or keep lists alive longer, so allocation per node also grew somewhat.

The numbers above are reasoning, not a measurement of this code.

## Decision rule: profile first

Run a search benchmark and look at allocation and GC time in Dart DevTools before doing this. If `generate` and move-ordering allocations are not near the top of the profile, the change is optional. As a rough guide, if GC and allocation are under about 5% of search time, skip it for now. Changing the generator signature later costs the same as changing it now, so there is no penalty for waiting until the profile says it matters.
