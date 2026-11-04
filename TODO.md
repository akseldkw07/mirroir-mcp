# TODO (akseldkw07 fork)

Work for this fork of [jfarcand/mirroir-mcp](https://github.com/jfarcand/mirroir-mcp). The
porting plan is in `akseldkw07/iphone-mirror-mcp`, `docs/mirroir-mcp-merge-proposal.md`.

## Ports from iphone-mirror-mcp

- [x] Cover guard (#1), verified on device with a floating panel over the phone
- [x] `swipe` reports whether the screen moved, retries a dropped gesture (#2), verified on device
- [x] `scroll_to_top`: clock taps until two in a row change nothing (#6), verified on device
- [x] `read_scrolling_list`: overlapping page images (#6, #7)
- [x] On-device run of `read_scrolling_list` after #7 (2026-11-03, Settings): 4 pages to the end,
      every pair overlapping (shifts 342, 260, 208 rows), no rows lost, 15 s.
- [x] Opt-in focus restore (`restoreFocus` / `MIRROIR_RESTORE_FOCUS`): gives focus back once input
      goes quiet and no tool call is running (#14). On device (2026-11-03): Finder front, a
      swipe brought iPhone Mirroring forward, Finder was front again 5 s later.
- [x] Natural-scrolling sign: not needed. On device (2026-11-03) with natural scrolling off, a
      swipe with the finger moving up scrolled Settings down (content moved up 241 px), the same
      as with it on. Synthesized scroll events aren't flipped by the setting, so upstream's fixed
      sign is right either way.
- [x] Switch the MCP client configs from `iphone-mirror-mcp` (Python) to this fork's binary,
      then archive `akseldkw07/iphone-mirror-mcp` (2026-11-03; Claude Desktop verified)
- [ ] Run the FakeMirroring integration tests (CI only: they reset the display and post input;
      GitHub's free-tier macOS runners are slow, so they lag behind merges)

## Open iPhone Mirroring automatically

Today every tool fails with "Target 'iphone' is not running. Launch iPhone Mirroring first."
when the app is closed, and `doctor` only suggests `open -a 'iPhone Mirroring'`. Open it
instead, so nobody has to do it by hand before a session:

- [x] Open it by bundle ID (`open -g -b`) when it isn't running or has no window, and wait for
      its window (#13). Verified on device: `scroll_to_top` from closed, connected, at the top.
- [x] On the "Unlock Your iPhone" screen (no AX elements; read by OCR), press Connect once and
      report "unlock your iPhone to continue" (#13). Unit-tested; not yet seen on device.
- [x] Once per tool call in `ensureConnected` / `prepareTarget`, with an opt-out
      (`autoLaunch` / `MIRROIR_AUTO_LAUNCH`) (#13).
- [ ] Report the other states it can't fix by name: not signed in, or not paired.
- [ ] A `mirror_launch` tool, or `status(launch: true)`, to open it on demand.
- [ ] A FakeMirroring integration test that starts from "not running".

## Repo setup

- [x] Pre-commit hooks: upstream's `.githooks` plus `mcp-utils/precommit/fork-block.yaml` (#9, #12)
- [ ] Before offering a port upstream: agree to `CLA.md` (opening an issue or PR upstream counts
      as signing it; there's no separate step), and reword the commits to upstream's rules
      (conventional, at most 2 lines, no AI attribution lines). Upstream merges locally and has
      taken no outside PRs, so ask in an issue first.
