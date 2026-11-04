// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Opt-in (restoreFocus): gives focus back to the app that had it before input to the mirror.
// ABOUTME: Waits until input goes quiet, so a run of taps or swipes switches focus only once.

import AppKit
import Foundation
import HelperLib
import os

/// Whether a tool call is running. The restore waits for it: a long `type_text` can outlast
/// the quiet period, and keys posted after the switch would go to the other app.
final class ToolCallActivity: Sendable {
    static let shared = ToolCallActivity()
    private let running = OSAllocatedUnfairLock(initialState: 0)

    func begin() { running.withLock { $0 += 1 } }
    func end() { running.withLock { $0 = max(0, $0 - 1) } }
    var isBusy: Bool { running.withLock { $0 > 0 } }
}

/// Which app is frontmost, and making an app frontmost.
protocol FocusSwitching: Sendable {
    func frontmostPID() -> pid_t?
    func activate(pid: pid_t) -> Bool
}

/// Live focus: the window server's frontmost window owner, and System Events for the switch
/// (works across Spaces, like `ensureTargetFrontmost`).
struct SystemFocusSwitcher: FocusSwitching {
    func frontmostPID() -> pid_t? {
        RunningAppLocator.frontmostWindowOwner()?.processIdentifier
    }

    func activate(pid: pid_t) -> Bool {
        let script = NSAppleScript(source: """
            tell application "System Events"
                set frontmost of (first process whose unix id is \(pid)) to true
            end tell
            """)
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let err = errorInfo { DebugLog.log("focus", "restore failed: \(err)") }
        return errorInfo == nil
    }
}

/// Gives focus back to the app that was frontmost before the server brought the mirror forward.
///
/// `willActivate` records the app being left, `noteInput` marks each later input, and once
/// no input has arrived for `delayUs` the previous app is made frontmost again, unless the
/// user has switched somewhere else in the meantime (then focus is theirs to keep).
final class FocusRestorer: @unchecked Sendable {
    private let focus: any FocusSwitching
    private let delayUs: UInt32
    private let schedule: @Sendable (UInt32, @escaping @Sendable () -> Void) -> Void
    private let isBusy: @Sendable () -> Bool
    private let lock = NSLock()
    private var previous: pid_t?
    private var target: pid_t?
    private var generation = 0

    init(focus: any FocusSwitching, delayUs: UInt32,
         schedule: @escaping @Sendable (UInt32, @escaping @Sendable () -> Void) -> Void,
         isBusy: @escaping @Sendable () -> Bool = { ToolCallActivity.shared.isBusy }) {
        self.focus = focus
        self.delayUs = delayUs
        self.schedule = schedule
        self.isBusy = isBusy
    }

    /// The live restorer when `restoreFocus` is on, else nil.
    static var configured: FocusRestorer? {
        guard EnvConfig.restoreFocus else { return nil }
        return FocusRestorer(focus: SystemFocusSwitcher(), delayUs: EnvConfig.restoreFocusDelayUs,
                             schedule: { delayUs, work in
                                 DispatchQueue.global().asyncAfter(
                                     deadline: .now() + .microseconds(Int(delayUs)), execute: work)
                             })
    }

    /// The server is about to bring `target` forward over `previous`.
    func willActivate(target: pid_t, previous: pid_t?) {
        guard let previous, previous != target else { return }
        let gen: Int = lock.withLock {
            self.previous = previous
            self.target = target
            generation += 1
            return generation
        }
        arm(gen)
    }

    /// Input went to the mirror: start the quiet period again.
    func noteInput() {
        let gen: Int? = lock.withLock {
            guard previous != nil else { return nil }
            generation += 1
            return generation
        }
        if let gen { arm(gen) }
    }

    private func arm(_ gen: Int) {
        schedule(delayUs) { [weak self] in self?.fire(gen) }
    }

    private func fire(_ gen: Int) {
        if isBusy() {
            let current = lock.withLock { generation }
            if gen == current { arm(gen) }  // still the latest: wait out another quiet period
            return
        }
        let pending: (previous: pid_t, target: pid_t)? = lock.withLock {
            guard gen == generation, let previous, let target else { return nil }
            self.previous = nil
            self.target = nil
            return (previous, target)
        }
        guard let pending else { return }
        // Only take focus back from the mirror itself; if the user moved on, leave it.
        guard focus.frontmostPID() == pending.target else {
            DebugLog.log("focus", "restore skipped: the mirror is no longer frontmost")
            return
        }
        DebugLog.log("focus", "restoring focus to pid \(pending.previous)")
        _ = focus.activate(pid: pending.previous)
    }
}
