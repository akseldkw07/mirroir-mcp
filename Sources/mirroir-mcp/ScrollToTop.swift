// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: scroll_to_top: taps the iOS status-bar clock until two taps in a row change nothing.
// ABOUTME: Taps get lost, so one still tap isn't proof; a probe swipe isn't either (overscroll holds).

import CoreGraphics
import Foundation
import HelperLib

/// Scroll the frontmost iOS list back to its top (pure orchestration over input and capture).
///
/// A status-bar tap at the top of a list changes nothing, so two still taps in
/// a row mean the top (or two lost taps in a row, which is rare). Verifying with
/// a probe swipe instead was measured to fail: pulling down at the top stretches
/// headers (e.g. a Phone app contact card) and iOS can hold the overscroll, so the
/// probe always reads as movement.
enum ScrollToTop {
    enum Outcome: Equatable {
        /// A tap was refused or failed.
        case failed(String)
        /// `atTop` is whether two taps in a row changed nothing; `effect` compares
        /// the screen before the first tap with the end (nil when it couldn't be captured).
        case done(atTop: Bool, taps: Int, effect: SwipeEffect?)
    }

    static let maxTaps = 4
    /// Taps in a row that must leave the screen unchanged.
    static let stillTapsNeeded = 2
    /// Pause after a tap for the scroll-to-top animation to start.
    static let tapSettleUs: UInt32 = 600_000

    /// The status-bar clock, in window points. Measured on the iPhone Mirroring
    /// window: left of the Dynamic Island, in the status bar row.
    static func clockPoint(windowSize: CGSize) -> CGPoint {
        CGPoint(x: (windowSize.width * 0.176).rounded(), y: (windowSize.height * 0.08).rounded())
    }

    static func run(input: any InputProviding, capture: any ScreenCapturing, windowSize: CGSize,
                    settleTimeoutUs: UInt32 = EnvConfig.frameSettleTimeoutUs,
                    pause: (UInt32) -> Void = { usleep($0) }) -> Outcome {
        let first = capture.captureWithInfo().flatMap { GrayFrame(png: $0.data, size: $0.info.size) }
        let clock = clockPoint(windowSize: windowSize)
        var previous = first
        var still = 0
        for tap in 1 ... maxTaps {
            if let error = input.tap(x: clock.x, y: clock.y, cursorMode: nil) { return .failed(error) }
            pause(tapSettleUs)
            guard let prior = previous,
                  let shot = capture.captureSettledWithInfo(timeoutUs: settleTimeoutUs),
                  let current = GrayFrame(png: shot.data, size: shot.info.size),
                  current.width == prior.width, current.height == prior.height
            else { return .done(atTop: false, taps: tap, effect: nil) }
            still = SwipeMovement.effect(before: prior, after: current, distance: 0).moved ? 0 : still + 1
            previous = current
            if still >= stillTapsNeeded {
                return .done(atTop: true, taps: tap, effect: overall(first, current))
            }
        }
        return .done(atTop: false, taps: maxTaps, effect: previous.flatMap { overall(first, $0) })
    }

    /// The screen at the end compared with the screen before the first tap.
    private static func overall(_ first: GrayFrame?, _ last: GrayFrame) -> SwipeEffect? {
        first.map { SwipeMovement.effect(before: $0, after: last, distance: 0) }
    }

    /// The tool's result text (nil for `.failed`, which is an error).
    static func message(_ outcome: Outcome) -> String? {
        guard case .done(let atTop, let taps, let effect) = outcome else { return nil }
        guard let effect else {
            return "Tapped the status bar; not verified: the screen could not be captured."
        }
        guard atTop else {
            return "Not verified at the top: the screen still changed after \(taps) status-bar taps."
        }
        let checked = "At the top of the list (\(stillTapsNeeded) status-bar taps in a row changed "
            + "nothing; \(taps) taps)"
        return effect.moved
            ? "\(checked); the screen moved (diff_ratio \(effect.diffRatio))."
            : "\(checked); it was already there."
    }
}
