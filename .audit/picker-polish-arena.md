# Arena synthesis: picker polish

## Phase C
Skipped. Cross-judge pool first alternate (`gemini-4-neon-high` for unavailable `gemini-4-argon-medium`) failed: weekly usage. Not re-running on `grok-4.7-high-fast` (same vendor as candidate-2). Operator scored both designs.

## Rubric (operator)

| Criterion | c1 | c2 |
|-----------|----|----|
| Coverage 1/2/3/5/6/7 | 5 | 5 |
| Honest no-cwd dedupe | 3 | 5 |
| Minimal surface | 3 | 5 |
| Testability | 4 | 5 |
| Visible failure | 4 | 5 |
| Compatibility | 4 | 5 |

## Base
candidate-2 (`/tmp/arena-rex-navigator/candidate-2/DESIGN.md`)

Why: unique-basename coverage avoids false hides; missing `rex.ui` fails at pick so `choice`/`self_check` still load; empty `items` needs no dummy id; `select_launches` owns hide/rank/cap.

## Grafts from candidate-1
1. `MAX_LAUNCHES = 48` (c1's 64 spirit + BRIEF ~top 50; reject c2's 20 as too tight for filter-only UI).
2. Named constants `CURRENT_DETAIL` / `OPEN_DETAIL` (both had them; keep explicit).
3. Reject c1 load-time module error and `i:empty` info row.

## Rejected
c1 five-rule `launch_covered_by_session`; c1 silent-or-load-time UI stub; score shown in UI.
