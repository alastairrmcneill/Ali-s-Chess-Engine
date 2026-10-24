# Magic bitboards for V12

A step-by-step guide to replacing the classical ray-and-bitscan slider attacks in `lib/engines/v12/core/sliders.dart` with magic bitboard lookups. This replaces the Milestone 7 stub in `bitboard_plan.md`.

It is written so you can implement it yourself. Every step says **what** you're building, **why**, and **how**, with snippets you can adapt. Each step ends with a checkpoint: don't move on until it passes.

---

## 0. Where we are now

`Sliders.rookAttacks(sq, occ)` does this today:

1. For each of 4 directions, load the empty-board ray `rays[sq * 8 + dir]`.
2. `ray & occ` gives the blockers on that ray.
3. If there are any, bitscan to the *first* one (`lsb` for increasing directions, `msb` for decreasing) and clear everything behind it using that blocker's own ray.

That's ~4 table loads, 4 branches, up to 4 bitscans (each a de Bruijn multiply plus a table load, and `msb` also has a 6-step smear), and a handful of ORs. A queen does 8 of those. It's correct and already fairly quick, but it is branchy and does a lot of work for something called from every move generation, every pin/check detection and every `isAttacked` test.

Callers today (all in V12):

| Caller | Calls |
|---|---|
| `board.dart:235` (`isSquareAttacked`-style test) | `rookAttacks`, `bishopAttacks` |
| `move_generator.dart:50` (checkers) | `rookAttacks`, `bishopAttacks` |
| `move_generator.dart:88` (pins, `occ = 0` for snipers) | `rookAttacks`, `bishopAttacks` |
| `move_generator.dart:126-128` (piece moves) | passes `s.bishopAttacks` / `s.rookAttacks` / `s.queenAttacks` as **tear-offs** into `_sliderMoves` |
| `move_generator.dart:186` (en passant discovered check) | `rookAttacks`, `bishopAttacks` |

Note that `Board` and `MoveGenerator` each construct their own `Sliders` (`static final Sliders _sliders = Sliders(_tables)` and `static final Sliders s = Sliders(a)`). That matters in step 5.

### The goal

Replace those loops with **one multiply, one shift and one array load**:

```
attacks = table[offset[sq] + (((occ & mask[sq]) * magic[sq]) >>> shift[sq])]
```

### Ground rules

- The public API (`rookAttacks`, `bishopAttacks`, `queenAttacks`, all `(int sq, int occ) -> int`) does **not** change. No caller edits needed.
- The current classical code is **kept** as `rookAttacksSlow` / `bishopAttacksSlow`. It is the oracle for tests and the table builder.
- Magic stays only if it is measurably faster in AOT. Step 8 is the decision.

---

## 1. How magic bitboards work (read this once, it makes the rest obvious)

A rook on `d4` attacks different squares depending on which pieces are in its way. Blockers only matter if they sit on the rook's rays. And a blocker on the **last** square of a ray (the board edge) never matters, because the ray ends there anyway: the attack set is identical whether or not it's occupied.

So the attack set depends only on the occupancy of the **relevant squares**: the rays minus their final edge squares. For a rook that's at most 12 squares, for a bishop at most 9. That's at most 2^12 = 4096 distinct situations per square, so we can precompute every answer.

The problem is turning a sparse 64-bit `occ & mask` into a dense index 0..4095. That's what the magic multiply does:

```
index = ((occ & mask) * magic) >>> (64 - bits)
```

Multiplying by a well-chosen constant makes the relevant bits "land" in the top `bits` bits in some order, and the shift moves them down to form an index. A magic number is **good** if no two occupancies with *different* attack sets map to the same index. Two occupancies with the *same* attack set colliding is fine (a "constructive collision"), and it's what lets the table be smaller than a perfect packing.

We can't derive magics, we find them by random search (step 3).

### Why this works so well in Dart

- Dart's native `int` is 64-bit two's complement, and `*` wraps silently on the VM. That is exactly the semantics magics need.
- You must use `>>>` (logical shift), never `>>`. `(occ & mask) * magic` is very often negative, and `>>` would sign-extend and give a garbage index. This is the same rule the rest of `bitboard.dart` follows.
- This does **not** work on Dart web (ints are doubles there). Not an issue: V12 already requires native.

### Sizes (use these as sanity checks later)

| | Per-square bits | Total entries | Bytes (8 each) |
|---|---|---|---|
| Rook | 10, 11 or 12 | **102,400** | ~800 KB |
| Bishop | 5 to 9 | **5,248** | ~41 KB |

Rook corners have 12 bits, rook edge squares 11, rook inner squares 10. If your totals differ from 102,400 / 5,248, your masks are wrong.

The ~800 KB rook table is bigger than a typical L1 cache and comparable to L2. That is the main reason magic is "measure, don't assume" (step 8).

---

## 2. Relevance masks

**What:** for each square, `rookMask(sq)` and `bishopMask(sq)`: the empty-board attack rays with the board-edge squares removed.

**Why:** the mask picks out exactly the occupancy bits that can change the answer. It's used in three places (generator, table builder, runtime lookup) so it must live in **one** function.

**How:** the key point is that edge removal is **per direction**, not "remove all edge squares". A rook on `a4` still needs `a5, a6, a7` (north along the a-file) even though they're on the a-file; only `a8` (the end of that ray) is dropped. A rook on `a4` going east needs `b4..g4` but not `h4`.

In your a8 = 0 mapping:

| Direction | Ray's last square lies on | Remove with |
|---|---|---|
| N (towards rank 8) | rank 8 | `& ~RANK_8` |
| E | h-file | `& ~FILE_H` |
| S | rank 1 | `& ~RANK_1` |
| W | a-file | `& ~FILE_A` |

Bishops are simpler: every diagonal ray ends on *some* edge, so the combined diagonal rays just lose all four edges.

Create `lib/engines/v12/core/slider_masks.dart`:

```dart
import 'package:ace/engines/v12/core/attack_tables.dart';
import 'package:ace/engines/v12/core/bitboard.dart';

// Direction indexes match AttackTables.rays (rays[sq * 8 + dir]).
const int _n = 0, _e = 1, _s = 2, _w = 3, _ne = 4, _se = 5, _sw = 6, _nw = 7;

const int _edges = RANK_8 | RANK_1 | FILE_A | FILE_H;

/// Squares whose occupancy can change a rook's attacks from [sq]: each ray minus its last square.
int rookMask(AttackTables t, int sq) {
  final r = t.rays;
  return (r[sq * 8 + _n] & ~RANK_8) |
      (r[sq * 8 + _e] & ~FILE_H) |
      (r[sq * 8 + _s] & ~RANK_1) |
      (r[sq * 8 + _w] & ~FILE_A);
}

/// Same for a bishop. Every diagonal ray ends on an edge, so drop all edges at once.
int bishopMask(AttackTables t, int sq) {
  final r = t.rays;
  return (r[sq * 8 + _ne] | r[sq * 8 + _se] | r[sq * 8 + _sw] | r[sq * 8 + _nw]) & ~_edges;
}
```

(`_edges` is a `const` expression built from consts, so it's fine.)

**Checkpoint (add to a new `test/engines/v12/slider_masks_test.dart`):**

- `rookMask` for `a8` has 12 bits set, for `d4` has 10, for `a4` has 11. Bishop `a8` has 6, `d4` has 9, `h1` has 6.
- Sum of `1 << popCount(rookMask)` over 64 squares == **102400**, bishop == **5248**.
- Neither mask contains its own square (rays exclude it already).
- Print `BitOps.toAscii(rookMask(t, d4))` once and eyeball it.

---

## 3. The magic generator

**What:** `tool/generate_magics.dart`, a one-off script that finds a magic number for each square and each piece and writes `lib/engines/v12/core/magic_numbers.dart`.

**Why:** published magics (the ones on chessprogramming.org) assume a1 = 0. Your board is a8 = 0, which is a vertical flip. Flipping the square index does not flip a magic multiplication's behaviour, so published numbers are wrong for your masks. Generate your own, and commit the output so the build never depends on running the tool.

**How, in four pieces.**

### 3a. Enumerate all occupancy subsets of a mask (Carry-Rippler)

To try a magic we need every possible occupancy of the mask bits, paired with its true attack set.

```dart
// Visits every subset of [mask], including 0 and mask itself.
// subset = (subset - mask) & mask is the "Carry-Rippler" trick: it counts through the subsets in order.
int subset = 0;
do {
  // ... use subset
  subset = (subset - mask) & mask;
} while (subset != 0);
```

It relies on 64-bit wrapping subtraction, which Dart gives you.

For each subset, the reference answer comes from the **classical** routine (`Sliders.rookAttacksSlow(sq, subset)`), which is already covered by `sliders_test.dart` against a naive walk. Don't write a third implementation.

### 3b. Candidate magics

Good magics are *sparse* (few bits set), so AND three random numbers:

```dart
int _random64(Random r) => (r.nextInt(1 << 32) << 32) | r.nextInt(1 << 32);
int _sparse(Random r) => _random64(r) & _random64(r) & _random64(r);
```

Use a fixed seed (`Random(12345)`) so the output is reproducible.

Quick reject before the expensive collision check: a usable magic must push plenty of mask bits into the top byte.

```dart
if (BitOps.popCount((mask * magic) >>> 56) < 6) continue;
```

(Use `>>> 56`, not `& 0xFF00000000000000`. That hex literal is above 2^63 and reads awkwardly in Dart.)

### 3c. The collision test

```dart
/// Returns a magic with no destructive collisions for this mask, or null if [maxTries] ran out.
int? _findMagic(int mask, List<int> occs, List<int> refs, Random rng, {int maxTries = 100000000}) {
  final bits = BitOps.popCount(mask);
  final shift = 64 - bits;
  final size = 1 << bits;
  final used = Uint64List(size); // attack set stored at each index
  final stamp = Int32List(size); // which attempt wrote that index; avoids refilling `used` every try

  for (int attempt = 1; attempt <= maxTries; attempt++) {
    final magic = _sparse(rng);
    if (BitOps.popCount((mask * magic) >>> 56) < 6) continue;

    bool ok = true;
    for (int i = 0; i < occs.length; i++) {
      final idx = (occs[i] * magic) >>> shift;
      if (stamp[idx] != attempt) {
        stamp[idx] = attempt; // first write this attempt
        used[idx] = refs[i];
      } else if (used[idx] != refs[i]) {
        ok = false; // destructive collision: same index, different attack set
        break;
      }
    }
    if (ok) return magic;
  }
  return null;
}
```

Why a `stamp` array instead of a sentinel: an attack set can legitimately be any value, and clearing `used` on every one of millions of attempts is wasteful. A stamp tells you "has this slot been written during *this* attempt?" for free.

Note `occs[i] * magic` is used without masking again: `occs[i]` is already a subset of `mask`.

### 3d. Driver and output

```dart
// dart run tool/generate_magics.dart
void main() {
  final tables = AttackTables();
  final sliders = Sliders(tables);
  final rng = Random(12345);

  final rook = <int>[], bishop = <int>[];
  for (int sq = 0; sq < 64; sq++) {
    rook.add(_generate(sq, rookMask(tables, sq), sliders.rookAttacksSlow, rng));
    bishop.add(_generate(sq, bishopMask(tables, sq), sliders.bishopAttacksSlow, rng));
  }
  // write the file, see below
}

int _generate(int sq, int mask, int Function(int sq, int occ) slow, Random rng) {
  final occs = <int>[], refs = <int>[];
  int subset = 0;
  do {
    occs.add(subset);
    refs.add(slow(sq, subset));
    subset = (subset - mask) & mask;
  } while (subset != 0);

  final magic = _findMagic(mask, occs, refs, rng);
  if (magic == null) throw StateError('no magic found for sq $sq');
  return magic;
}
```

Output file. **Print as signed decimal** (`magic.toString()`): many magics have bit 63 set and are negative `int`s in Dart, and `toRadixString(16)` on a negative gives `-7f...`, not what you want. Decimal always round-trips.

```dart
final sb = StringBuffer()
  ..writeln('// GENERATED by tool/generate_magics.dart (seed 12345). Do not edit.')
  ..writeln('// Square mapping: a8 = 0. Regenerate if the mapping or the mask definition changes.')
  ..writeln()
  ..writeln('const List<int> rookMagics = [')
  ..writeln(rook.map((m) => '  $m,').join('\n'))
  ..writeln('];')
  ..writeln()
  ..writeln('const List<int> bishopMagics = [')
  ..writeln(bishop.map((m) => '  $m,').join('\n'))
  ..writeln('];');
File('lib/engines/v12/core/magic_numbers.dart').writeAsStringSync(sb.toString());
```

Then `dart format` the output.

**Deliberate deviation from the old plan:** the plan had the generator also emit per-square bit counts. Don't. The bit count is `popCount(mask)` and the shift is `64 - bits`; both are derivable at startup from the mask. Storing them invites the file and the mask function drifting apart. The only thing that can't be derived is the magic itself.

**Run time:** the generator runs under JIT and may take from a few seconds up to a minute; rook corners and the bishop squares with many bits are the slow ones. Print a line per square so you can see progress. If a square takes absurdly long, your mask or reference function is wrong (a *correct* setup finds a magic within a few million tries).

**Checkpoint:** the script finishes, `magic_numbers.dart` has 64 + 64 entries, re-running produces a byte-identical file (determinism).

---

## 4. Rename the classical code to `*Slow`

**What:** in `sliders.dart`, rename `rookAttacks` to `rookAttacksSlow` and `bishopAttacks` to `bishopAttacksSlow`. Leave `_increasing` / `_decreasing` alone. Keep `queenAttacks` for now but have it call the **slow** pair for the moment.

**Why:** you need the oracle to exist under its own name *before* the fast version takes over the public names. Then the generator (step 3) and the table builder (step 5) can use it, and tests can compare the two.

Do this step **before** step 3: the generator needs `*Slow`. The order in section 10 is the real order of work.

Temporarily the old public names won't exist; add thin forwarding methods so everything compiles and the test suite stays green while you work:

```dart
int rookAttacks(int sq, int occupied) => rookAttacksSlow(sq, occupied);
int bishopAttacks(int sq, int occupied) => bishopAttacksSlow(sq, occupied);
```

**Checkpoint:** `flutter test test/engines/v12` fully green; perft tests unchanged.

---

## 5. Build the lookup tables and switch the fast path on

**What:** at first use, for each piece type fill a flat `Uint64List` with the attack set for every relevant occupancy of every square; then make `rookAttacks` / `bishopAttacks` do the one-multiply lookup.

**Why:** the table is what the magic index points into. Filling it at startup from the oracle (instead of generating a 100K-entry source file) keeps the repo small and makes the table correct by construction.

### 5a. A small holder class

Put this private class in `sliders.dart`:

```dart
/// Everything needed to look up one piece type's attacks.
class _MagicTable {
  final Uint64List masks = Uint64List(64);
  final Uint64List magics = Uint64List(64);
  final Uint8List shifts = Uint8List(64);
  final Int32List offsets = Int32List(64);
  late final Uint64List attacks;

  _MagicTable(
    List<int> magicNumbers,
    int Function(int sq) maskFor,
    int Function(int sq, int occ) slow,
  ) {
    int total = 0;
    for (int sq = 0; sq < 64; sq++) {
      final mask = maskFor(sq);
      final bits = BitOps.popCount(mask);
      masks[sq] = mask;
      magics[sq] = magicNumbers[sq];
      shifts[sq] = 64 - bits;
      offsets[sq] = total;
      total += 1 << bits;
    }

    attacks = Uint64List(total);
    for (int sq = 0; sq < 64; sq++) {
      final mask = masks[sq], magic = magics[sq], shift = shifts[sq], offset = offsets[sq];
      int subset = 0;
      do {
        attacks[offset + ((subset * magic) >>> shift)] = slow(sq, subset);
        subset = (subset - mask) & mask;
      } while (subset != 0);
    }
  }
}
```

Each square gets a slice of the shared array starting at `offsets[sq]`, of length `1 << bits`.

### 5b. Share the tables, don't rebuild per `Sliders`

`Board` and `MoveGenerator` each create a `Sliders`. Without care you'd build and hold two 800 KB tables per isolate. Cache in statics:

```dart
class Sliders {
  static _MagicTable? _rookShared;
  static _MagicTable? _bishopShared;

  final Uint64List _rays;
  final _MagicTable _rook;
  final _MagicTable _bishop;

  Sliders(AttackTables tables)
      : _rays = tables.rays,
        _rook = _rookShared ??= _buildRook(tables),
        _bishop = _bishopShared ??= _buildBishop(tables);
```

The builders need `rookAttacksSlow`, which is an instance method that needs `_rays`. Easiest: make a throwaway helper that only needs the rays, e.g. a private top-level function `_slowRook(Uint64List rays, int sq, int occ)` that both the instance method and the builder call. Alternatively make `rookAttacksSlow` / `bishopAttacksSlow` take their rays from `tables.rays` via a tiny private `Sliders._slow(tables)` constructor. Pick whichever reads more cleanly; the requirement is only: *the builder must not call the fast path* (it would read a table that doesn't exist yet).

```dart
static _MagicTable _buildRook(AttackTables t) {
  final slow = Sliders._slowOnly(t);
  return _MagicTable(rookMagics, (sq) => rookMask(t, sq), slow.rookAttacksSlow);
}
```

Each isolate (engine worker) has its own statics, so each pays the build once: ~107K calls to the slow routine, a few milliseconds.

### 5c. The fast path

```dart
int rookAttacks(int sq, int occupied) {
  final t = _rook;
  return t.attacks[t.offsets[sq] + (((occupied & t.masks[sq]) * t.magics[sq]) >>> t.shifts[sq])];
}

int bishopAttacks(int sq, int occupied) {
  final t = _bishop;
  return t.attacks[t.offsets[sq] + (((occupied & t.masks[sq]) * t.magics[sq]) >>> t.shifts[sq])];
}

int queenAttacks(int sq, int occupied) => rookAttacks(sq, occupied) | bishopAttacks(sq, occupied);
```

Notes:

- `queenAttacks` now just ORs the two fast lookups.
- Typed lists, not `const List<int>`: in AOT a `const List<int>` holding values beyond Smi range stores boxed `Mint` objects (pointer chase per load). `Uint64List` reads are unboxed.
- The `>>>` result is always in `[0, 2^bits)`, so the index is in range; but Dart still emits a bounds check on every typed-list access. Step 7 covers reducing loads.
- Do not mask the rook/bishop's own square out of `occupied` manually: the mask already excludes it, so a piece on the slider's own square is ignored (this is the existing `the slider square itself in the occupancy is ignored` test).

**Checkpoint:** all of `sliders_test.dart` (hand-checked cases + naive-walk comparison) now runs against the *fast* path. It should pass untouched. Then run the full perft suite.

---

## 6. Tests

The existing tests already cover the public names, so they now verify the magic path against a naive walk. Add these on top in `sliders_test.dart`:

**6a. Exhaustive: this proves the table, not just samples it.** For every square, walk *every* subset of the mask (the same Carry-Rippler loop), and require `rookAttacks == rookAttacksSlow`. That's 102,400 + 5,248 checks total, essentially instant, and covers every distinct relevant occupancy.

```dart
test('rook magic == slow, every relevant occupancy', () {
  for (int sq = 0; sq < 64; sq++) {
    final mask = rookMask(tables, sq);
    int subset = 0;
    do {
      expect(sliders.rookAttacks(sq, subset), sliders.rookAttacksSlow(sq, subset),
          reason: 'sq=${BoardHelper.squareName(sq)} occ=0x${subset.toRadixString(16)}');
      subset = (subset - mask) & mask;
    } while (subset != 0);
  }
});
```

(Same for bishops.)

**6b. Irrelevant bits don't leak.** For random full 64-bit occupancies, magic == slow. This checks that the mask really removes everything that shouldn't matter (e.g. blockers on edge squares, far-away pieces).

**6c. Table sizes.** Expose the totals (a `@visibleForTesting` getter, or test the masks directly as in step 2) and check 102400 / 5248.

**6d. Same table across instances.** `identical(Sliders(t1)._rook, Sliders(t2)._rook)` style test (or just a test that constructing many `Sliders` is fast), to guard the static sharing.

**6e. Perft.** Re-run the existing perft tests. Any magic bug shows up here as a wrong node count.

---

## 7. Optional micro-optimizations (only after step 8 shows magic is worth keeping)

Each of these is a separate experiment: do one, re-benchmark, keep or revert.

1. **Cut typed-list loads per lookup.** Currently 5 loads (`masks`, `magics`, `shifts`, `offsets`, `attacks`). Interleave the per-square data into two arrays: `Uint64List data` as `[mask0, magic0, mask1, magic1, ...]` and `Int32List meta` as `[offset0, shift0, ...]`. Fewer distinct arrays, better locality.
2. **Pre-add the offset into the shift.** Store `shift` and `offset` as ints in a single `Int32List` entry pair, or store per-square `Uint64List` *views* (`Uint64List.sublistView(attacks, offset, offset + size)`) so the final load is just `view[index]`. Views add an indirection of their own, so measure.
3. **Remove the tear-off in `_sliderMoves`.** `_sliderMoves(bb, s.rookAttacks, ...)` passes a closure, so every attack lookup is an indirect, non-inlinable call. If the benchmark shows magic barely helping at the perft level, this call overhead may be hiding the gain. Replace the function parameter with a piece-type switch, or three small specialised loops.
4. **Pins use `occ = 0`.** `move_generator.dart:88` computes `rookAttacks(ksq, 0)` for snipers. That's constant per king square: it equals the empty-board rook attack, i.e. `rays[N] | rays[E] | rays[S] | rays[W]`. Precomputing 64 values for rook and 64 for bishop removes two lookups per generate call. Not magic-specific, but it's a free win while you're here.

---

## 8. Benchmark and decide

**What:** answer "is magic faster **in this engine, in AOT**?"

**Why:** the textbook 1.3-2x assumes C-like speed and a classical routine that is slower than yours. Your classical routine is already tight, Dart bounds-checks every typed-list read, and an 800 KB table pressures cache. Magic could win big, small, or even lose. Don't merge on faith.

Always benchmark AOT, never `dart run` (JIT numbers are not representative of the Flutter release build):

```
dart compile exe tool/bench_sliders.dart -o /tmp/bench_sliders && /tmp/bench_sliders
```

### 8a. Micro-benchmark: `tool/bench_sliders.dart`

Isolate just the attack functions.

- Precompute a `Uint64List` of ~4096 occupancies **before** timing (don't time the RNG).
- Use *realistic* densities. Uniform random 50% occupancy is far denser than a real position; mix `r & r` (~25%), `r & r & r` (~12%) and some `r | r` (~75%). A middlegame has ~20-28 pieces on 64 squares.
- Loop `sq = i & 63`, `occ = occs[i & 4095]`, and fold the result into a checksum (`sum ^= attacks`), then **print the checksum**. Otherwise the optimiser can delete the loop.
- Do a warm-up pass, then time several repetitions of ~20M calls and take the best or median.
- Time `rookAttacksSlow`, `rookAttacks`, `bishopAttacksSlow`, `bishopAttacks` separately, then queen both ways.
- Assert the two checksums are **equal**: it doubles as another correctness test.

```dart
int run(int Function(int, int) f, Uint64List occs, int reps) {
  int sum = 0;
  for (int r = 0; r < reps; r++) {
    for (int i = 0; i < occs.length; i++) {
      sum ^= f(i & 63, occs[i]);
    }
  }
  return sum;
}
```

Caveat: passing `f` as a function makes the call indirect for both candidates equally, so it's fair for *comparison* but understates the absolute gain. For the most honest micro numbers, write two copies of the loop calling the methods directly.

### 8b. Macro-benchmark: perft and search

The micro number is an upper bound; what you care about is whole-engine speed.

- **Perft nps.** `V12Engine().perft(fen, depth)` already exists. Reuse the position list from `tool/bench_v11.dart` (its `perftCases` hold known node counts), time before and after, and report knps. Perft is slider-heavy, so it's a good probe.
- **Fixed-depth search nps** with the searcher, same idea as `bench_v11.dart`. Node counts and best moves must be **identical** before and after (this is a pure speed-up); only nps changes.
- To compare, build the AOT binary on the classical commit, then on the magic commit. Or temporarily point the public methods at the `*Slow` versions with a flag. Don't compare JIT to AOT or runs on a hot/cold machine.

Record results in a short table at the bottom of this file (Results log).

### 8c. Decision rule

| Result | Action |
|---|---|
| Perft/search nps up by roughly 10% or more, node counts identical | Keep magic |
| Micro faster but macro flat or negative | Try step 7 items 1 and 3; if still flat, revert the public API to the slow versions |
| Magic slower | Revert. Keep the generator, magic file and tests on a branch; classical stays the default |

"Revert" is cheap by design: `*Slow` stays in the file, so it's a two-line change to the public methods.

---

## 9. Pitfalls checklist

- **Used published magics.** They assume a1 = 0. Generate your own.
- **`>>` instead of `>>>`.** Gives negative or huge indices and a `RangeError`.
- **Mask drift.** Generator and runtime must call the same `rookMask` / `bishopMask`. If you changed the mask definition, regenerate.
- **Masking edges globally for rooks.** A rook mask must remove only the *end of each ray*. Removing all edge squares breaks rooks on the a/h files and ranks 1/8.
- **Calling the fast path while building the table.** The builder must use `*Slow`.
- **Hex literals ≥ 2^63.** Legal on native but they read as negative; emit decimal in the generated file and use `>>> 56` instead of `0xFF00...`.
- **Two tables per isolate.** `Board` and `MoveGenerator` both create `Sliders`; share the tables statically.
- **Web.** `Uint64List` and 64-bit wrap don't exist there. Out of scope, as already stated in `bitboard_plan.md`.
- **Benchmarking JIT.** Numbers don't transfer to release builds.

---

## 10. Order of work

| # | Step | Done when |
|---|---|---|
| 1 | Masks (`slider_masks.dart`) + mask tests | bit counts and 102400/5248 sums match |
| 2 | Rename to `*Slow`, add forwarding methods | all tests green, nothing else changed |
| 3 | `tool/generate_magics.dart` → `magic_numbers.dart` | file has 128 entries, rerun is byte-identical |
| 4 | `_MagicTable` + shared statics + fast path | existing slider tests pass on the fast path |
| 5 | Exhaustive and random magic-vs-slow tests, perft | all green |
| 6 | `tool/bench_sliders.dart` and perft/search nps before vs after | numbers in the results log |
| 7 | Keep or revert (step 8 rule); try step 7 tweaks if kept | decision recorded |

Budget: about half a day, most of it in the generator and the benchmark.

---

## Results log

| Date | Change | Micro rook (ns/call) | Micro bishop (ns/call) | Perft knps | Search knps | Decision |
|---|---|---|---|---|---|---|
| | classical baseline | | | | | |
| | magic | | | | | |
