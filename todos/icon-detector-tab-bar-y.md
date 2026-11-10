# Icon detector places iOS 26 tab-bar icons about 25 pt too low

Found 2026-11-10 while fixing the tab-bar tap point (Clock app, iOS 26, window 292x645).

## What happens

- `describe_screen` listed "Unlabeled icons" at (61, 622), (124, 621), (187, 623), (250, 622).
- In the full-resolution capture the tab icons span y 590-605 (centers about 597) and the glass
  bar ends at y 623, so the reported centers sit on the bar's bottom edge.

## To do

- Capture the frame again and check whether the detector's boxes or its pixel-to-point
  mapping is off (the window was 1x; the OCR path divides by the image height, see
  `AppleVisionTextRecognizer`).
- Write a failing test from that capture, fix it, and recheck on the device by tapping a
  reported icon.
