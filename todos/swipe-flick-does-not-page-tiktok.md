# A flick does not page TikTok's feed

Found 2026-11-17/18 on a real iPhone (iOS 26, Spanish UI, iPhone Mirroring on macOS 27).

`swipe` from (130, 460) to (130, 30) in 150 ms (about 2900 pt/s, above the 2000 pt/s flick
speed) in TikTok's "Para ti" feed reports "the screen moved" (diff_ratio 0.31 to 0.56), but
the caption and author read back the same afterwards: the feed stayed on the same video.
The diff is the video playing, not a page change.

| Build | Result |
| --- | --- |
| `main` at `348c46c` (0.47.0) | Same video after the flick (1 try) |
| PR #28 at `0228f23` (0.48.0 and the input fixes) | Same video after the flick (3 tries) |

So PR #28 did not cause it. On the same day a slow left swipe on the Home Screen paged
cleanly on the PR #28 build, and left the Home Screen parked between two pages on `main`.

## To do

1. Reproduce with a screenshot before and after, to rule out an OCR coincidence.
2. Check which path the swipe took (window-addressed or HID) and whether the trackpad
   sender ID is found on this Mac (`TrackpadScrollFields.senderDeviceID`).
3. Try a longer flick and other paging feeds (Reels, Shorts) to see whether it is TikTok only.
4. `swipe` should not report success from diff_ratio alone on a playing video.
