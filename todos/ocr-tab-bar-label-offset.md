# OCR places iOS 26 tab-bar labels about 30 pt too high

Found 2026-11-08 while validating PR #19 on a real iPhone (Spanish UI, Clock app).

## What happens

- `describe_screen` reports the glass tab-bar labels ("Cronómetro", "Timers", "Reloj mundial",
  "Alarmas") at y≈608, while the labels sit at y≈640 in the screenshot (window 304x671).
- `tap(text: "Timers")` therefore taps above the tab bar and misses.
- Tapping the tab icons by coordinates (y≈626) works.

## To do

- Find where the offset comes from: the OCR bounding box on the translucent iOS 26 tab bar,
  or the tap-point lift applied to labels in the bottom band.
- Write a failing test from a real OCR capture of the Clock tab bar, then fix it so
  `tap(text:)` lands on tab-bar items.
- Recheck on the device: `tap(text:)` on each Clock tab switches it.
