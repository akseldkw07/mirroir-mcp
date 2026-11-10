# launch_app fails often on a real iPhone

Found 2026-11-09/10 on a real iPhone (iOS 26, Spanish UI, iPhone Mirroring on macOS 27), on
both `main` and the upstream sync branch (#23). Opening the same apps by hand (Home Screen
search pill, type the name, tap the top-hit icon) worked every time, so the apps and the
keyboard path are fine; `launch_app`'s own steps are what fail.

## Failures seen

| App | Message | What the screen showed |
| --- | --- | --- |
| TikTok (x2) | "Spotlight lists no app as its top result" | Top hit was the TikTok app icon, label OCR'd as "TIkTok" at about (54, 185); messages, links and a Settings row "TikTok / Apps" below |
| Safari | "Spotlight lists no app as its top result" | Top hit was the Safari app icon, label OCR'd as "Satari"; "Google" to its right; a Settings row "Safari / Apps" below |
| Reloj (x3), Clock | "Spotlight did not open (or the screen could not be read)" | Home Screen; the search pill opened Spotlight fine right after |
| Safari, TikTok | "Typed '...' into Spotlight but it never appeared on screen" | iPhone Mirroring was not the Mac's front app; keystrokes were fine once it was (the advice to quit and reopen Mirroring was wrong) |
| Reloj (once) | Launched | — |

## Likely causes to check

- **Top-hit check:** it seems to require the OCR'd label to match the name. A one-letter
  misread ("Satari", "TIkTok") fails it, and the Settings row with the exact name and "Apps"
  under it may be read as the top result instead.
- **Opening Spotlight:** the swipe-down (or shortcut) that opens Spotlight misses often; the
  Home Screen "Buscar" pill tap never did.
- **Front app:** typing while iPhone Mirroring is not frontmost loses the keystrokes, and the
  error blames the session instead of focus.

## To do

1. **Open an issue upstream** in `jfarcand/mirroir-mcp` with the table above (ask before
   posting; no personal data from the screenshots).
2. **Search the web** for other projects that launch iOS apps reliably through iPhone
   Mirroring or Spotlight (other iPhone Mirroring MCP servers or automation tools,
   Appium/XCUITest launchers, Shortcuts-based launchers) and note how they pick the result
   and confirm the launch.
3. Capture the failing Spotlight screens (TikTok, Safari) as fixtures and write failing
   tests for the top-hit check; make it tolerate OCR misreads (e.g. compare against the
   app-icon row position, or fuzzy match) and ignore Settings rows.
4. Make opening Spotlight fall back to the Home Screen search pill when the first attempt
   shows no search field.
5. Check focus before typing; when iPhone Mirroring is not frontmost, bring it forward
   instead of telling the user to quit and reopen it.
6. Recheck on the device: `launch_app` for TikTok, Safari and Reloj, five times each.
