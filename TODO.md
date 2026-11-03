# TODO (akseldkw07 fork)

Work for this fork of [jfarcand/mirroir-mcp](https://github.com/jfarcand/mirroir-mcp). The
porting plan is in `akseldkw07/iphone-mirror-mcp`, `docs/mirroir-mcp-merge-proposal.md`.

## Ports from iphone-mirror-mcp

- [x] Cover guard (#1), verified on device with a floating panel over the phone
- [x] `swipe` reports whether the screen moved, retries a dropped gesture (#2), verified on device
- [x] `scroll_to_top`: clock taps until two in a row change nothing (#6), verified on device
- [x] `read_scrolling_list`: overlapping page images (#6, #7)
- [ ] On-device run of `read_scrolling_list`'s overshoot recovery (#7). Settings showed a scroll
      ratio of 1.15-2.6x per swipe; check that no rows fall between pages on a long list.
- [ ] Opt-in focus restore (give the previous app focus back after each action)
- [ ] Natural-scrolling sign: upstream ignores the setting; the Python original measured that
      it flips the direction. Check on a Mac with natural scrolling off.
- [ ] Switch the MCP client configs from `iphone-mirror-mcp` (Python) to this fork's binary,
      then archive `akseldkw07/iphone-mirror-mcp`
- [ ] Run the FakeMirroring integration tests (CI only: they reset the display and post input;
      GitHub's free-tier macOS runners are slow, so they lag behind merges)

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
