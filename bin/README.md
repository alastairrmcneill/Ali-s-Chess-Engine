# `match.dart` — engine-vs-engine match runner

A command-line tool that plays one engine version against another over a batch of
games from a fixed opening book, and reports the result (W/D/L, Elo difference,
terminations, per-engine search stats) once the whole match is finished.

## Running it

```bash
dart run bin/match.dart --a <engineId> --b <engineId> [options]
```

Example — test v2 against the v1 baseline, 500 games at 200ms/move:

```bash
dart run bin/match.dart --a v2 --b v1 --games 500 --movetime 200
```

List the engine ids you can use for `--a`/`--b`:

```bash
dart run bin/match.dart --list
```

## Flags

| Flag              | Required | Default         | Meaning                                                                                                                                                          |
| ----------------- | -------- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--a <id>`        | yes      | —               | Engine A's id — the engine being tested. Shown first in every result (e.g. `A ${stats.total}`, Elo is A minus B).                                                |
| `--b <id>`        | yes      | —               | Engine B's id — the baseline/opponent to compare A against.                                                                                                      |
| `--games <n>`     | no       | `1000`          | Total number of games to play. Should be even: games are scheduled in pairs (one opening played twice, once with each engine as White) so colours stay balanced. |
| `--movetime <ms>` | no       | `100`           | Fixed thinking time per move, in milliseconds, given to both engines.                                                                                            |
| `--max-moves <n>` | no       | `300`           | Moves per side (so `2n` plies) after which an unfinished game is declared a draw.                                                                                |
| `--out <dir>`     | no       | `match_results` | Accepted but not currently used — the output folder is always `match_results/<timestamp>_<a>-vs-<b>`.                                                            |
| `--list`          | no       | off             | Print every known engine id (one per line) and exit. Use this to see valid values for `--a`/`--b`.                                                               |
| `--help`, `-h`    | no       | off             | Print usage and exit.                                                                                                                                            |

`--a` and `--b` must both be ids known to `EngineRegistry` (check with `--list`).
Passing an unknown id, or omitting `--a`/`--b`, prints an error and the usage
text, and exits with code `64`.

## What happens when it runs

1. Loads the built-in opening book (`lib/match/opening_book_data.dart`, 500
   pre-balanced lines). Any lines the book had to skip are printed as warnings.
2. Creates engine A and engine B via `EngineRegistry.create`.
3. Plays `games` games in pairs: for each opening, one game with A as White and
   B as Black, then the same opening again with colours swapped. This cancels
   out any inherent advantage in a given opening line. The whole match runs to
   completion — there's no way to stop it early and still get a summary.
4. Once every game has been played, writes the match config and the full
   summary (text and JSON) to the output folder, and prints the final summary
   to the terminal.

## Output folder contents

Everything is written under `match_results/<timestamp>_<a>-vs-<b>`:

- The match config actually used (engine ids, games, move time, max moves,
  opening count, and any warnings from the opening book).
- A plain-text summary (W/D/L, Elo ± error, score by colour, termination
  breakdown, average depth/nodes/time per engine).
- The same summary as JSON, for scripting/plotting.

Note: individual games are not currently logged to a PGN file — `MatchRunner`
only returns the aggregated `MatchStats` once the match is complete, so there's
no per-game hook left to write one.
