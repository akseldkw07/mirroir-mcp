# TODO (akseldkw07 fork)

Work for this fork of [jfarcand/mirroir-mcp](https://github.com/jfarcand/mirroir-mcp). The
porting plan is in `akseldkw07/iphone-mirror-mcp`, `docs/mirroir-mcp-merge-proposal.md`.

## Ports from iphone-mirror-mcp

- [ ] PR 1: cover guard (open: #1)
- [ ] PR 2: `swipe` reports whether the screen moved, retries a dropped gesture (open: #2)
- [ ] PR 3: `scroll_to_top` (status-bar clock tap, verified by an upward probe)
- [ ] PR 4: page images for a whole list (`read_scrolling_list`)
- [ ] PR 5: opt-in focus restore; decide the natural-scrolling sign
- [ ] On-device acceptance test (the list in iphone-mirror-mcp's `TODO.md`)

## Open iPhone Mirroring automatically

Today every tool fails with "Target 'iphone' is not running. Launch iPhone Mirroring first."
when the app is closed, and `doctor` only suggests `open -a 'iPhone Mirroring'`. Open it
instead, so nobody has to do it by hand before a session:

- [ ] When `getState()` is `.notRunning` (or `.noWindow`), launch it by bundle ID
      (`EnvConfig.mirroringBundleID`, `com.apple.ScreenContinuity`) with `NSWorkspace`,
      without stealing focus where possible, then wait for `.connected` with a timeout.
- [ ] Report the states it can't fix by itself, by name: the phone is unlocked or in use
      (Mirroring pauses; the phone must be locked and nearby), not signed in, or not paired.
- [ ] Do it once per tool call in `ensureConnected` (a shared preamble), and add an opt-out
      setting (`autoLaunch` / `MIRROIR_AUTO_LAUNCH`).
- [ ] A `mirror_launch` tool, or `status(launch: true)`, to open it on demand.
- [ ] Tests: a launcher protocol with a stub (no real launches in unit tests), plus a
      FakeMirroring integration test that starts from "not running".

## Repo setup

- [ ] Pre-commit hooks: keep upstream's `.githooks`, and add `mcp-utils/precommit/fork-block.yaml`
      once mcp-utils' `feat/shared-precommit` is merged (see its README, "Setting up a new
      server repo").
- [ ] Before offering a port upstream: sign `CLA.md`, and reword its commit to upstream's
      rules (conventional, at most 2 lines, no AI attribution lines).
