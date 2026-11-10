# Input refused as "paused" right after typing

Found 2026-11-10 on a real iPhone (iOS 26) through iPhone Mirroring on macOS 27; seen on
`main` (after typing "Reloj" in Spotlight, 2026-11-09) and on the #23 sync branch.

## What happens

- After `type_text("abc")` into Spotlight (iOS capitalized it to "Abc"), the next
  `press_key` was refused: "'iphone' is not accepting input. The window says: “Abc” [close]".
- The screenshot showed live Spotlight results, and `mirroir-mcp ax-capture` a few seconds
  later read the window as `connected`. The retry went through.
- Likely a transient macOS overlay (the autocorrect/capitalization bubble) in the Mirroring
  window's AX tree: `MirroringWindowResolver.state` reads any labeled text as `paused`.

## To do

- Capture the AX tree while the bubble shows (`ax-capture --watch`) and confirm what it is.
- Write a failing `MirroringWindowResolver` test from that capture; don't read that overlay
  as an interruption.
- Recheck on the device: type a lowercase word into Spotlight, then press a key at once.
