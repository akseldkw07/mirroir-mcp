// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Opens iPhone Mirroring when it isn't running, frees a paused session, and presses Connect on its unlock screen.
// ABOUTME: The phone must still be unlocked by its owner; that case gets a clear "unlock" message.

import AppKit
import CoreGraphics
import Foundation
import HelperLib

/// Starts the mirroring app.
protocol MirroringLaunching: Sendable {
    /// Launch the app without taking focus. Returns false if it couldn't be launched.
    func launch() -> Bool
}

/// `open -g -b <bundle id>`: launches (or reopens the window of) the app in the background.
struct WorkspaceMirroringLauncher: MirroringLaunching {
    let bundleID: String

    func launch() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-b", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

/// How `ensureConnected` recovers a mirroring target that isn't ready for input.
struct MirroringRecovery: Sendable {
    /// Opens the app when it isn't running or has no window; nil turns that off.
    let launcher: (any MirroringLaunching)?
    /// How long to wait for the window after launching.
    let launchTimeoutUs: UInt32
    /// Posts a real click at a screen point (Connect on the unlock screen).
    let click: @Sendable (CGPoint) -> Void

    /// No launching. The default, so tests and other targets never start an app.
    static let none = MirroringRecovery(
        launcher: nil, launchTimeoutUs: 0, click: { _ = CGEventInput.click(at: $0, targetPID: nil) })

    /// The real iPhone Mirroring target: open it unless `MIRROIR_AUTO_LAUNCH=0`.
    static var live: MirroringRecovery {
        MirroringRecovery(
            launcher: EnvConfig.autoLaunch
                ? WorkspaceMirroringLauncher(bundleID: EnvConfig.mirroringBundleID) : nil,
            launchTimeoutUs: EnvConfig.autoLaunchTimeoutUs,
            click: { _ = CGEventInput.click(at: $0, targetPID: nil) })
    }
}

extension InputSimulation {

    /// Ready for input: open the app or press Connect if needed (the `ensureConnected` preamble).
    func prepareTarget(tag: String) -> String? {
        ensureConnected(tag: tag)
    }

    /// Open the mirroring app if it isn't running or has no window, and wait for its window.
    /// Returns nil when there's nothing to do or it opened, else what went wrong.
    func openMirroringIfNeeded(tag: String) -> String? {
        guard let launcher = recovery.launcher, bridge is MenuActionCapable else { return nil }
        let missing: (WindowState) -> Bool = { $0 == .notRunning || $0 == .noWindow }
        guard missing(bridge.getState()) else { return nil }
        DebugLog.log(tag, "auto-open: launching \(EnvConfig.mirroringBundleID)")
        guard launcher.launch() else {
            return "Couldn't open iPhone Mirroring (\(EnvConfig.mirroringBundleID)). Open it by hand and retry."
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(recovery.launchTimeoutUs) * 1000
        while missing(bridge.getState()), DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(100_000)
        }
        guard !missing(bridge.getState()) else {
            let seconds = Double(recovery.launchTimeoutUs) / 1_000_000
            return "Opened iPhone Mirroring, but it has no window after \(seconds) s. If it shows a "
                + "sign-in or pairing prompt on the Mac, finish that, then retry."
        }
        DebugLog.log(tag, "auto-open: window is up")
        return nil
    }

    /// On iPhone Mirroring's "Unlock Your iPhone" screen (no accessibility elements, so read
    /// by OCR), press Connect once. The phone still has to be unlocked by its owner.
    /// Returns nil if this screen isn't shown or the session connected, else the message.
    func pressConnectOnUnlockScreen(tag: String) -> String? {
        guard bridge.getState() == .paused, bridge is MenuActionCapable,
              let elements = pasteVerifier?.describe()?.elements,
              let connect = Self.unlockScreenConnect(in: elements),
              let info = bridge.getWindowInfo()
        else { return nil }
        let point = CGPoint(x: info.position.x + CGFloat(connect.tapX),
                            y: info.position.y + CGFloat(connect.tapY))
        if let coverError = coverRefusalIfEnabled(screenPoints: [point], info: info, tag: tag) {
            return coverError
        }
        DebugLog.log(tag, "unlock screen: pressing Connect at (\(Int(point.x)), \(Int(point.y)))")
        recovery.click(point)
        usleep(EnvConfig.resumeFromPausedUs)
        if bridge.getState() == .connected { return nil }
        return "iPhone Mirroring shows \"Unlock Your iPhone\"; I pressed Connect. Unlock your iPhone "
            + "(Face ID or passcode) to continue, then retry."
    }

    /// Free a session suspended by a target interruption (on iPhone Mirroring: the
    /// "iPhone camera is not available from Mac" OK dialog, or the plain "click to
    /// resume" overlay) by running the registered `SessionEscapePlugin`s. The
    /// framework is target-agnostic; the bundled plugins handle iPhone Continuity
    /// dialogs via a real mouse click that frees the session even when CGEvent
    /// input to the device is rejected. Interruptions can re-arm, so it retries.
    /// Returns true if the session is connected (or was never paused).
    func freePausedSession(tag: String) -> Bool {
        guard bridge.getState() == .paused else { return true }
        let click = escapeClick()
        for attempt in 0 ..< EnvConfig.pausedDismissClickAttempts {
            DebugLog.log(tag, "session paused — running escape plugins " +
                "(attempt \(attempt + 1)/\(EnvConfig.pausedDismissClickAttempts))")
            // Try registered escape plugins in order (camera dialog → resume overlay).
            guard SessionEscapeRegistry.attemptEscape(
                bridge: bridge, click: click, tag: tag) else {
                // No plugin recognized this interruption — nothing more to try.
                // A previous attempt's click can still be taking effect (the
                // overlay fades after the session resumes), so give it the
                // resume settle time before reporting the session as paused.
                if attempt > 0 { usleep(EnvConfig.resumeFromPausedUs) }
                return bridge.getState() == .connected
            }
            usleep(EnvConfig.resumeFromPausedUs)
            if bridge.getState() == .connected {
                DebugLog.log(tag, "session freed — now connected")
                return true
            }
        }
        return bridge.getState() == .connected
    }

    /// The Connect button below an "Unlock Your iPhone" heading, if the OCR shows both.
    static func unlockScreenConnect(in elements: [TapPoint]) -> TapPoint? {
        guard let heading = elements.first(where: {
            $0.text.lowercased().contains("unlock your iphone")
        }) else { return nil }
        return elements.first {
            $0.text.trimmingCharacters(in: .whitespaces).lowercased() == "connect"
                && $0.tapY > heading.tapY
        }
    }
}
