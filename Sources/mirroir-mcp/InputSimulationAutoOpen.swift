// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Opens iPhone Mirroring when it isn't running, and presses Connect on its unlock screen.
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
