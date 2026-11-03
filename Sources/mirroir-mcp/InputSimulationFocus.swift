// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Brings the target window to the front before input (moved out of InputSimulation.swift).
// ABOUTME: Uses System Events for cross-Space activation; a click sent before focus settles is lost.

import AppKit
import Foundation
import HelperLib

extension InputSimulation {

    /// Ensure the target window is the frontmost app so it receives input.
    /// Always activates, since focus can move between the check and the input;
    /// the check only decides whether to sleep for Space-switch settling.
    ///
    /// Activation state comes from the freshly resolved target itself, not from
    /// `NSWorkspace.frontmostApplication`, which is frozen in a server that
    /// never runs its main run loop (see `RunningAppLocator`).
    ///
    /// When the target is already the active app, this returns without touching
    /// focus at all: the System Events `set frontmost` call disturbs event
    /// routing for a beat even when it is a no-op, and a click posted inside
    /// that window is silently dropped (measured against FakeMirroring — the
    /// same tap delivers with no AppleScript, or with AppleScript plus the
    /// settle sleep, but never with AppleScript and no settle).
    ///
    /// Uses AppleScript `set frontmost to true` via System Events for
    /// cross-Space activation (NSRunningApplication.activate() cannot trigger
    /// a macOS Space switch, deprecated in macOS 14).
    ///
    /// - Returns: `true` if the window was not already frontmost (focus changed).
    @discardableResult
    func ensureTargetFrontmost() -> Bool {
        let target = bridge.findProcess()
        let alreadyFront = target?.isActive ?? false

        if alreadyFront {
            DebugLog.log("focus", "target already active — skipping activation")
            return false
        }
        if DebugLog.enabled {
            let front = RunningAppLocator.frontmostWindowOwner()?.bundleIdentifier ?? "nil"
            DebugLog.log("focus", "switching from \(front)")
        }

        // Resolve the process name for the current target's running application.
        // For iPhone Mirroring this is the configured process name; for generic
        // targets it's the app's localized name from NSRunningApplication.
        let processName: String
        if bridge is MirroringBridge {
            processName = EnvConfig.mirroringProcessName
        } else if let app = target, let name = app.localizedName {
            processName = name
        } else {
            // Fallback: use NSRunningApplication.activate() directly
            bridge.activate()
            usleep(EnvConfig.spaceSwitchSettleUs)
            return true
        }

        let script = NSAppleScript(source: """
            tell application "System Events"
                tell process "\(processName)"
                    set frontmost to true
                end tell
            end tell
            """)
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)

        if let err = errorInfo {
            DebugLog.log("focus", "AppleScript error: \(err)")
        }

        // The settle sleep is not just for Space switches: a click posted
        // before the activation transition finishes is silently dropped.
        usleep(EnvConfig.spaceSwitchSettleUs)

        if DebugLog.enabled {
            let after = RunningAppLocator.frontmostWindowOwner()?.bundleIdentifier ?? "nil"
            DebugLog.log("focus", "after activation frontApp=\(after)")
        }
        return true
    }
}
