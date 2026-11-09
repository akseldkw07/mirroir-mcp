// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Live text-entry boundaries: key events posted through CGEventInput and the general pasteboard.
// ABOUTME: InputSimulation types and pastes through these, so tests can swap them for doubles.

import AppKit
import CoreGraphics
import Foundation

/// Live `KeyEventPosting`: forwards to `CGEventInput`, which posts to the HID
/// event tap where iPhone Mirroring reads keyboard events, or to one process.
struct CGEventKeyPoster: KeyEventPosting {

    func postKey(keycode: UInt16, flags: CGEventFlags, targetPID: pid_t?) -> Bool {
        CGEventInput.postKey(keycode: keycode, flags: flags, targetPID: targetPID)
    }

    func postKeySequence(_ sequence: CGKeySequence, targetPID: pid_t?) -> Bool {
        CGEventInput.postKeySequence(sequence, targetPID: targetPID)
    }
}

/// Live `ClickPosting`: forwards to `CGEventInput`, which posts to the HID
/// event tap at a screen point, or to one process.
struct CGEventClickPoster: ClickPosting {

    func click(at point: CGPoint, targetPID: pid_t?) -> Bool {
        CGEventInput.click(at: point, targetPID: targetPID)
    }

    func doubleClick(at point: CGPoint, targetPID: pid_t?) -> Bool {
        CGEventInput.doubleTap(at: point, targetPID: targetPID)
    }

    func longPress(at point: CGPoint, durationMs: Int, targetPID: pid_t?) -> Bool {
        CGEventInput.longPress(at: point, durationMs: durationMs, targetPID: targetPID)
    }
}

/// Live `PasteboardAccessing`: `NSPasteboard.general`, the pasteboard
/// Universal Clipboard syncs to the iPhone. Only the plain-text flavor is
/// read and written.
struct GeneralPasteboard: PasteboardAccessing {

    func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func replaceContents(with text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
