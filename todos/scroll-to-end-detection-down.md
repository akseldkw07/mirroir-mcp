# scroll_to misses the end of a list when scrolling down

Found 2026-11-10 on a real iPhone (iOS 26, Clock app, world-clock list, window 292x645) while
checking PR #23 (upstream m13 `ScrollSeeker`).

## What happens

- At the bottom of the list (last row "Tokio" visible), `scroll_to(label: "<missing>")`
  scrolls the whole budget and returns `stop_reason=max_scrolls` (8 of 8, then 12 of 12).
- Scrolling up on the same list stops correctly with `end_of_content` after 5 scrolls.
- The call still ends and reports the label as not found; it only wastes scrolls and gives
  the wrong reason.

## To do

- Record the reads at the bottom (likely the list pulled past its end, or the tab bar's glass
  over the last row, changing the text share between reads) and compare with
  `scrollUnchangedTextShare` / `scrollRevisitDepth`.
- Write a failing `ScrollSeeker` test from those reads, fix it, recheck on the device.
- Check upstream `jfarcand/mirroir-mcp` first; open an issue there if it is not known.
