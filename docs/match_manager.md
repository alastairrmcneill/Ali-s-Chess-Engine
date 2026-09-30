# Match manager

Plays two engine versions against each other from balanced openings, so you can tell whether a change actually
made ACE stronger. It works like the match setup in Sebastian Lague's
[chess bot video](https://youtu.be/_vqlIPDR2TU): 500 opening positions, each played twice with colours swapped,
giving 1,000 games.

It runs from the command line (fastest, for big matches) or on your phone. Both save the same files.

## Quick start

```sh
# Desktop: v2 vs v1, 1000 games, 100 ms per move, one game per spare CPU core
dart run bin/match.dart --engine1 v2 --engine2 v1

# Phone (dev-only entry point, the store app is unchanged). Use --release for full speed.
flutter run -t lib/main_match.dart --release
```

Press Ctrl+C to stop a CLI match early; you still get a report for the games played so far. On the phone, keep the
app open (the screen stays on while a match runs). Leaving the screen stops the match and saves what was played.

### CLI options

| option | default | |
| --- | --- | --- |
| `--engine1`, `--engine2` | latest | engine ids from `lib/engines/engine_registry.dart` |
| `--games` | 1000 | rounded up to an even number |
| `--movetime` | 100 | ms per move |
| `--movetime2` | same | give engine 2 a different time (handicap / sanity checks) |
| `--concurrency` | cores − 1 | games played at the same time |
| `--max-plies` | 500 | longer games are adjudicated as draws |
| `--opening-offset` | 0 | first opening line to use (0–499) |
| `--out` | `matches` | output folder (ignored by git) |

**Rough timing.** v1 games average about 110 engine moves after the 16 book moves, so 1,000 games at 100 ms is
about 3 hours of engine time. Divide that by `--concurrency` (e.g. about 1 hour on 3 cores). For quick checks use fewer games or less time per move,
but remember fewer games means a wider error margin.

## Reading the report

`report.txt` (also shown at the end of a CLI run and in the app's Report tab):

- **Score and Elo difference** are from engine 1's point of view, with a 95% confidence interval, e.g.
  `+45 ± 20`. If the interval includes 0 (e.g. `+15 ± 30`) the match hasn't shown a real difference yet. Play
  more games; the margin shrinks roughly with the square root of the number of games.
- **Likelihood of superiority** is the probability engine 1 is genuinely stronger, given the wins and losses.
- **How games ended**: mates, draws, and **illegal moves**. When an engine returns a move that isn't legal, the
  referee (`chess_core`) stops the game and that engine loses. The report lists every such game with the position
  and the move.
- **Engine stats**: average depth, nodes and time per move, and **time overruns** (moves that took more than 1.5×
  the allowed time + 50 ms).
- **Games lost after the loser reported ≥ +3.00**: games the engine threw away.
- **Suspicious moves**: moves after which the engine's *own* win chance (converted from its eval with Lichess's
  formula) fell by at least 20 percentage points by its next move. In other words, it missed something in its
  opponent's reply. They're sorted by how big the drop was, and marked with `?` in the PGN.

### PGN comments

`games.pgn` loads into Lichess (Study → import) or any chess GUI. Every engine move has a comment:

```
14. Ncb1 $2 {+7.75/2 30ms 3819 nodes; pv: Ncb1 Qxf2+ Bxf2; ? eval fell from +7.75 to +0.35 ...}
```

- `+7.75/2` is the eval in pawns from the moving side's point of view, followed by the depth completed.
- `30ms` and `3819 nodes` are the time used and nodes searched.
- `pv:` is the line the engine expected. It is often the best clue to *why* it played a move.
- `? ...` means the move was flagged as suspicious.
- Opening book moves are marked `{book}`.

## Inspecting a position

To see what an engine thinks the best few moves were in a position:

```sh
# A flagged move from a match (report.txt lists the game and ply of each one)
dart run bin/inspect.dart --engine v1 --pgn matches/<match>/games.pgn --game 12 --ply 34

# Any position
dart run bin/inspect.dart --engine v2 --fen "<FEN>" --top 5 --movetime 500
```

On the phone: open a saved match, tap a suspicious move (or any game), step to the move and tap **Inspect**.

Alpha-beta search only computes an exact score for the best move, so the inspector plays every legal move itself and
asks the engine to search the position after it. That gives a real top N for any engine version without changing
engine code. It is also handy for comparing versions: inspect the same position with v1 and v2.

## How it fits together

```
lib/chess_core/   rules and notation shared by everything: board, legal moves, FEN, UCI, SAN, game results.
                  This is the referee; it is kept correct (perft + a cross-check against python-chess).
lib/engines/      one frozen folder per version (v1/, v2/, ...) plus the ChessEngine interface and registry.
lib/match/        game runner, isolate pool, stats, PGN, report, opening book, storage.
lib/analysis/     position inspector.
lib/match_ui/     phone screens (entry point lib/main_match.dart).
bin/              match.dart and inspect.dart CLIs.
```

### The engine interface

Engines only exchange strings, like the UCI protocol, so each version can use whatever board representation it
wants internally:

```dart
Future<SearchResult> search(EnginePosition position, SearchLimits limits);
// EnginePosition: start FEN + the moves played since, in UCI notation ("e2e4", "e7e8q")
// SearchLimits:   moveTimeMs
// SearchResult:   bestMove (UCI), scoreCp or mateIn (side to move's view), depth, nodes, pv (UCI list)
```

The start FEN plus the move list (rather than just the current FEN) gives an engine the game history it needs for
repetition detection. An external UCI engine such as Stockfish could implement the same interface later by
launching it as a process on desktop.

**What's shared and what's per version.** Anything defined by the chess standards (FEN, UCI and SAN notation, the
rules) lives in `chess_core`, and every version uses it. Each version owns its board, move generator, search and
evaluation, plus a thin adapter (`vN_engine.dart`) that converts the shared FEN/UCI strings into its own types.

## Making a new version

```sh
dart run tool/new_engine_version.dart v2
```

This copies `lib/engines/v1` to `lib/engines/v2`, renames the adapter (`V2Engine`, "ACE v2"), registers it, and
makes it the version the store app plays. Then:

1. Make your improvements in `lib/engines/v2/`. Never edit an older version's folder; it has to keep playing
   exactly as it did so comparisons stay fair.
2. Run `flutter test`.
3. Run `dart run bin/match.dart --engine1 v2 --engine2 v1`.
4. Keep v2 if the Elo interval is clearly above 0.

Good first candidates are in [`engine_v1_known_issues.md`](engine_v1_known_issues.md). Fixing the illegal move bug
alone should be worth several percent of score, since v1 loses about 1 game in 20 to it.

If a new version changes its search info (for example it can report depth directly), update its adapter; v1's
adapter reads depth from v1's debug prints because v1's engine code is frozen.

## Checks

- **Self-play:** `dart run bin/match.dart --engine1 v1 --engine2 v1 --games 200 --movetime 40` should give an
  interval that includes 0. Over 200 games it gave `+38 ± 48`.
- **Handicap:** the same engine with 10× the thinking time should clearly win:
  `dart run bin/match.dart --engine1 v1 --engine2 v1 --movetime 20 --movetime2 200 --games 150`.
  Over 150 games this gave `-70 ± 56` for the 20ms side, which is significant. 40 games wasn't enough
  (`-108 ± 133`). The gap is modest because 10× the time only buys v1 about one extra ply (issue #6 in the known
  issues).
