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
4. ~~Make opening Spotlight fall back to the Home Screen search pill when the first attempt
   shows no search field.~~ Done differently in PR #28 (upstream 0.48): when Spotlight never
   shows the typed name, `launch_app` closes it and taps the app's Home Screen icon.
5. ~~Check focus before typing; when iPhone Mirroring is not frontmost, bring it forward
   instead of telling the user to quit and reopen it.~~ The wrong "quit and reopen" advice
   is gone in PR #28; the focus check itself was not verified.
6. ~~Recheck on the device: `launch_app` for TikTok, Safari and Reloj, five times each.~~
   Done, see below.

## Recheck on the device (PR #28)

| Date | Build | TikTok | Safari | Reloj |
| --- | --- | --- | --- | --- |
| 2026-11-15 | `69ea6e5` (0.48.0) | 5 of 5 | 5 of 5 | 5 of 5 |
| 2026-11-18 | `0228f23` plus the `EnvConfigAppIdentity` split (0.48.0 and the input fixes) | 4 of 5 | 6 of 6 | 5 of 5 |
| 2026-11-22 | `295ddbf` (0.50.3), mirror window 249x552 pt | 0 of 3 | 3 of 3 | 2 of 2 |

The one failure (TikTok, fourth launch in a row, 2026-11-18): "Spotlight did not show
'TikTok' after it was typed ... Opening it from its Home Screen icon failed too: the Home
Screen did not show (its search pill was not found)." The next launch worked. The Mac was in
use by hand at the time, which may have taken the keys.

TikTok on 2026-11-22: Spotlight showed "TikTak - Abrir" in the field and "Tik Tak" as the top
hit's label, so the top-hit check refused it ("Spotlight lists no app as its top result"). The
0.48.0 server gave the same error the same day, so this is the OCR misread from the table at
the top (step 3), not a change in 0.50.3. The mirror window was smaller than on the earlier
dates (249x552 against 259x573 pt), which may be why the misread now happens every time.
Contactos, Calendario and a Home Screen tap on "zoom" opened the first time.

Still open: steps 1 to 3. Step 3 now blocks TikTok at this window size.
