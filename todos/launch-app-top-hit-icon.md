# launch_app rejects an installed app that is Spotlight's top hit

Found 2026-11-10 on a real iPhone (iOS 26, Spanish UI) with TikTok installed.

## What happens

- `launch_app(name: "TikTok")` failed twice with "Spotlight lists no app as its top result".
- With the same query typed by hand, Spotlight's first section is the TikTok app icon with its
  label ("TIkTok" by OCR) at about (54, 185); messages, links and settings follow.
- Tapping the icon opened the app. Clock ("Reloj") launches fine the same way.

## To do

- Capture that Spotlight screen and find why the top-hit check rejects it: the OCR misread
  ("TIkTok"), or the TikTok results below it (messages, links, a Settings row named "TikTok").
- Write a failing test from the capture, fix it, and recheck `launch_app(name: "TikTok")`.
