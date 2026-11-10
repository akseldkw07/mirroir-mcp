# Confirm that shake reaches iOS through iPhone Mirroring

Found 2026-11-10 while checking PR #23 on a real iPhone (iOS 26, macOS 27).

## What happens

- `press_key("z", ["control", "command"])` returns "Pressed control+command+z" after text was
  typed into Safari's address bar, but no "Deshacer" (undo) prompt appears.
- The docs say iPhone Mirroring translates Ctrl+Cmd+Z into a device shake; that is not
  measured on this setup.

## To do

- With the user's OK, check Settings → Accesibilidad → Tocar → Agitar para deshacer on the phone.
- If it is on and still nothing happens, compare the iPhone Mirroring menu (is there a Shake
  item?) and the process-targeted key path against the HID path.
- Fix `shake` or document that it does nothing through iPhone Mirroring.
