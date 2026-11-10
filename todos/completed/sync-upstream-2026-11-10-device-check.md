> **Done 2026-11-10** (PR #23): upstream `39040c9..cff7e0b` synced and rebased onto `main`
> (with #24), CI green, device check passed: `scroll_to` direction semantics correct, quitting
> iPhone Mirroring is a stop that the server reports and never reverses. Deviations: `scroll_to`
> misses the end of a list going down, and `shake` has no visible effect; neither comes from
> this PR (upstream code, and the fork's unchanged shake path), so both moved to their own
> todos.

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
| `scroll_to` end detection, down | **Misses, reproducibly:** at the bottom of the same short list it returned `max_scrolls` after 8, and again after 12, not `end_of_content`. It still stops and reports the label as not found, so it costs scrolls but does no harm. Upstream's `ScrollSeeker` (new in m13), unchanged by the fork: not a merge blocker; see `todos/scroll-to-end-detection-down.md` |
| `shake` (Ctrl+Cmd+Z on the HID path) | Key sent ("Pressed control+command+z") with text typed in Safari's address bar, but no "Deshacer" (undo) prompt appeared. #23 keeps the fork's shake path (HID tap, Mirroring in front), so it behaves as on `main`: not a regression. Whether shake reaches iOS at all needs Shake to Undo checked on the phone; see `todos/shake-unconfirmed.md` |
| Quitting iPhone Mirroring mid-session | iPhone Mirroring went away mid-session (11:22). `status`: "Not running — 'iphone' is not open... It was running earlier and is gone now, and that is a stop: nothing reopens it for the agent." `scroll_to` failed ("Could not get window info for scroll"). Mirroring was running again at 11:23:21 showing "Timed Out"; the next `tap` was refused with the window's words. The user confirmed they reopened it: the server did not. Correct |

## Found along the way (own todos)

- `todos/launch-app-fails-often.md`: `launch_app` failed on most attempts (top-hit check,
  Spotlight not opening, focus).
- `todos/false-pause-autocorrect-bubble.md`: input refused as "paused" right after typing.
- `todos/icon-detector-tab-bar-y.md` (from #24).
