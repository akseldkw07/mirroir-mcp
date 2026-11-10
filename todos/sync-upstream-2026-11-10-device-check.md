# Finish PR #23 (upstream sync 2026-11-10): device check and merge

Branch `sync/upstream-2026-11-10`, PR #23. Status as of 2026-11-10 11:20 EST.

## Done

- Rebased onto `main` `b40fc33` (PR #24, tab-bar fix) and force-pushed with lease as
  `8096cff` (user approved the force push). CI rerunning on that head.
- Earlier CI failures fixed by the mcp-daily session: `Protocols.swift` back to 500 lines
  (registre gate passes); the ubuntu e2e "whole loop" judge-stub failure was a flake and
  passed on rerun.
- `scripts/unit-tests.sh` on the rebased branch: swift-testing 89 + 60 + 189 passed; XCTest
  2383 run, 3 failures from 2 tests that fail only on this Mac:
  - `RunningAppLocatorTests.testBundleIDLookupOnlyReturnsLiveProcesses`: a stale Contacts
    entry resolves to PID -1.
  - `SystemPhrasesTests.testTheSkillsCheckoutDeclaresTheLockScreenPhrases`: local
    `../mirroir-skills` is behind; `git -C ../mirroir-skills pull` fixes it (CI clones fresh).
- Release build of the rebased branch is what the MCP server runs (user ran `/mcp`).

## Device check (Tier 4)

| Item | Result |
| --- | --- |
| `scroll_to` direction (breaking: names the content wanted) | `down` revealed content further down (Clock world clock: header collapsed, "Tokio" appeared); `up` returned to the top; `scroll_to("Tokio")` found it after 2 scrolls. Correct |
| `scroll_to` end detection, up | `end_of_content` after 5 scrolls. Correct |
| `scroll_to` end detection, down | **Missed:** at the bottom of the same short list it returned `max_scrolls` after 8, not `end_of_content`. Rerun with `max_scrolls: 12` was interrupted; check it and file a todo or upstream issue if it repeats |
| `shake` (Ctrl+Cmd+Z on the HID path) | Key sent ("Pressed control+command+z") with text typed in Safari's address bar, but no "Deshacer" (undo) prompt appeared. Unconfirmed: either the shake does not reach iOS or Shake to Undo is off on the phone (not checked: Settings is off limits unless the user asks). Compare against `main` before merging |
| Quitting iPhone Mirroring mid-session | Not tested yet: needs the user to quit the app, then check that `status` says why and input is refused, and that the server does not reopen it |

## Found along the way (own todos)

- `todos/launch-app-fails-often.md`: `launch_app` failed on most attempts (top-hit check,
  Spotlight not opening, focus).
- `todos/false-pause-autocorrect-bubble.md`: input refused as "paused" right after typing.
- `todos/icon-detector-tab-bar-y.md` (from #24).

## To finish

1. Rerun `scroll_to` down to the end of a short list; decide whether the miss blocks #23
   (it is upstream's `ScrollSeeker`, new in m13).
2. Settle `shake`: try the same Safari test on a `main` build; if `main` shows the undo
   prompt and this branch does not, fix it here.
3. Quit-Mirroring test with the user.
4. Wait for CI on `8096cff`, sweep `todos/` (move this file to `todos/completed/` with a Done
   header), merge #23, run `mpgd`.
