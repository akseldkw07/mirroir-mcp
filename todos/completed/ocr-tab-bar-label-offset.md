> **Done 2026-11-10** (PR fix/ocr-tab-bar-label-offset): the OCR boxes were right; the tap-point
> lift was wrong. Tab-bar labels (icon rows in the bottom 10% of the window) are now tapped one
> label height above the label's top (`tapTabBarLabelLift`, 1.0) instead of the fixed 30 pt
> `tapIconOffset`, which home-screen icon rows keep. On the device, `tap(text:)` switched all
> four Clock tabs. Measured: glass bar y 578-623, icons 590-605, label tops 608, so the old
> tap point (578) sat on the bar's edge; the new one is about 598. TikTok (issue #15's app)
> is unaffected: its "+" button has no label, so its labels are spaced unevenly, the row is not
> an icon row, and they are tapped at their centers; `tap(text:)` switched its tabs.

# OCR places iOS 26 tab-bar labels about 30 pt too high

Found 2026-11-08 while validating PR #19 on a real iPhone (Spanish UI, Clock app).

## What happens

- `describe_screen` reports the glass tab-bar labels ("Cronómetro", "Timers", "Reloj mundial",
  "Alarmas") at y≈608, while the labels sit at y≈640 in the screenshot (window 304x671).
- `tap(text: "Timers")` therefore taps above the tab bar and misses.
- Tapping the tab icons by coordinates (y≈626) works.

## To do

- [x] Find where the offset comes from: the OCR bounding box on the translucent iOS 26 tab bar,
      or the tap-point lift applied to labels in the bottom band. (The lift.)
- [x] Write a failing test from a real OCR capture of the Clock tab bar, then fix it so
      `tap(text:)` lands on tab-bar items.
- [x] Recheck on the device: `tap(text:)` on each Clock tab switches it.
