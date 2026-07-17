# v0.1 dogfood log

This is the final behavioral gate for the source-only v0.1.0 Developer
Preview. Run Cockatoo normally for seven consecutive days. Avoid feature work
during the pass; only release-blocking fixes restart the clock.

## Window

- Start: 2026-07-17
- Target end: 2026-07-23 (after seven completed daily records)
- App commit: `566e215a21e513d27ecfa16cf8310806bf59779f`
- Restart note: the pass was re-pinned on 2026-07-17 before Day 1 was
  completed, after fixing the release-blocking Safari → Library open action.
- German pack SHA-256: `f4752a8f17e72c42ffcc83671ef15287aa12973c9a2b5f17b189e123fd71550b`
- macOS / Safari versions: macOS 15.7.5 / Safari 18.6

## What to exercise

- leave Cockatoo running across sleep/wake and Safari restarts;
- browse normal reading sites and inspect swaps/hover details;
- open the popup repeatedly, including while the app is quit;
- practise every day, including rebuild puzzles and wrong answers;
- use Overview, Library search/details, Settings, pause/resume, and menu bar;
- reload an already-open Safari tab after an extension rebuild once;
- on one day, quit Cockatoo while browsing, confirm cached swaps remain, then
  reopen it and confirm queued events drain.

Never include private page text, URLs, or personal vocabulary in this file.

## Daily record

| Day | Time used | Safari/extension state | Practice/progress state | Confusing UI | Crash/error | Result |
|---|---:|---|---|---|---|---|
| 1 |  |  |  |  |  | pending |
| 2 |  |  |  |  |  | pending |
| 3 |  |  |  |  |  | pending |
| 4 |  |  |  |  |  | pending |
| 5 |  |  |  |  |  | pending |
| 6 |  |  |  |  |  | pending |
| 7 |  |  |  |  |  | pending |

## Incidents

| ID | Date | Severity | Reproduction | Expected | Actual | Resolution |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

Severity guide:

- **blocker**: data corruption/loss, app cannot run, extension cannot connect;
- **high**: repeatable crash, stale state that requires reinstall, broken core control;
- **medium**: misleading state, surprising progress, serious usability friction;
- **low**: visual or copy issue that does not block the core loop.

## Exit decision

- [ ] seven daily records completed
- [ ] no unresolved blocker or high-severity incident
- [ ] no observed progress corruption or unexplained stage/box changes
- [ ] app-down/cache/queue recovery worked
- [ ] final `script/check.sh` passed at the recorded commit
- Decision: **pending**
- Signed by/date: _pending_
