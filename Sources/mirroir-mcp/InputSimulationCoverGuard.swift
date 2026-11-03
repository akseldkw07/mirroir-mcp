// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Cover guard: refuses pointing input when another app owns a point the input would touch.
// ABOUTME: Asks accessibility which app a click there would reach; the window list can't tell.

import AppKit
import ApplicationServices
import CoreGraphics
import HelperLib

/// The process that would receive a click at a screen point.
struct PointOwner: Equatable, Sendable {
    let pid: pid_t
    let name: String?
}

/// Answers which process owns a screen point.
protocol PointOwnerLocating: Sendable {
    /// The owner of `point` (global screen coordinates), or nil if it can't be told.
    func owner(at point: CGPoint) -> PointOwner?
}

/// Accessibility hit-test: the app whose element sits at the point.
///
/// The window list alone can't answer this: the Dock and Notification Center own
/// transparent full-screen windows above every app, so "topmost window containing
/// the point" falsely reports them as covering the target.
struct AccessibilityPointOwnerLocator: PointOwnerLocating {
    func owner(at point: CGPoint) -> PointOwner? {
        var element: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &element) == .success,
            let element else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName
        return PointOwner(pid: pid, name: name)
    }
}

extension InputSimulation {

    /// Refuses when any of `screenPoints` belongs to an app other than the target.
    ///
    /// Window captures show the target even when another window covers it, but
    /// HID input lands on whatever is on top: unchecked, a tap aimed at the phone
    /// can type or click into another Mac app's document. Activation brings the
    /// target above normal windows, so what's left are higher-layer windows such
    /// as notification banners and floating panels.
    /// Returns nil when every point is the target's, or the refusal message.
    func coverRefusal(screenPoints: [CGPoint], info: WindowInfo, tag: String) -> String? {
        for point in screenPoints {
            let owner = pointOwner.owner(at: point)
            if owner?.pid == info.pid { continue }
            let at = "(\(Int(point.x)), \(Int(point.y)))"
            let msg: String
            if let owner {
                let who = owner.name ?? "pid \(owner.pid)"
                msg = "Another window (\(who)) covers '\(bridge.targetName)' at screen point " +
                    "\(at); nothing was sent. Uncover the window and retry."
            } else {
                msg = "The cover check could not tell which app owns screen point \(at); " +
                    "nothing was sent. Check Accessibility permission, or set " +
                    "MIRROIR_COVER_GUARD=0 to skip the check."
            }
            DebugLog.log(tag, "REJECTED: \(msg)")
            return msg
        }
        return nil
    }

    /// The cover check for a pointing operation, after the target was activated.
    /// Skipped when events go straight to the target's process (cursor-free mode)
    /// or when the guard is turned off.
    func coverRefusalIfEnabled(screenPoints: [CGPoint], info: WindowInfo,
                               tag: String) -> String? {
        guard EnvConfig.coverGuard, cursorFreePID == nil else { return nil }
        return coverRefusal(screenPoints: screenPoints, info: info, tag: tag)
    }

    /// Screen points a swipe touches: start, the midpoint the scroll events are
    /// posted at (they go to the window under the cursor), and end.
    static func swipeInputPoints(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        return [start, mid, end]
    }
}
