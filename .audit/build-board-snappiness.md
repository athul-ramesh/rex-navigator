# build_board snappiness

Machine: darwin, 12 cores. Load averages during after runs: ~1.9 / 2.3 / 2.4.
Method: five alternating wall-clock samples via `rex.exec(python3 time.time())` around `M.build_board(nil)`.
Same harness before and after. One-run profile named the limiter as sequential `test`/`realpath` (`~347 ms` of `~560 ms`).

## Baseline (before batch resolve)

| run | ms | open | launches |
| --- | ---: | ---: | ---: |
| 1 | 552 | 3 | 147 |
| 2 | 574 | 3 | 147 |
| 3 | 567 | 3 | 147 |
| 4 | 573 | 3 | 147 |
| 5 | 547 | 3 | 147 |

Median **567 ms**. Range 547–574. Limiter: 2N `rex.exec` path checks.

## After (one python3 stdin resolve)

| run | ms | open | launches |
| --- | ---: | ---: | ---: |
| 1 | 188 | 3 | 149 |
| 2 | 193 | 3 | 149 |
| 3 | 188 | 3 | 149 |
| 4 | 212 | 3 | 149 |
| 5 | 194 | 3 | 149 |

Median **193 ms**. Range 188–212. Launch count drift is zoxide history, not logic.

Delta: **567 ms → 193 ms** median (~3.0×). self_check: ok.
