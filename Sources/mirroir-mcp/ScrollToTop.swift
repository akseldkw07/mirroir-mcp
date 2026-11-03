// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: scroll_to_top: taps the iOS status-bar clock and checks the list reached its top.
// ABOUTME: Taps get lost, so an upward probe swipe verifies it; still moving means tap again (up to 3).

import CoreGraphics
import Foundation
import HelperLib

/// Scroll the frontmost iOS list back to its top (pure orchestration over input and capture).
enum ScrollToTop {
    enum Outcome: Equatable {
        /// A tap or swipe was refused or failed.
        case failed(String)
        /// `atTop` is whether the probe confirmed the top; `effect` compares the
        /// screen before the first tap with the end (nil when it couldn't be captured).
        case done(atTop: Bool, taps: Int, effect: SwipeEffect?)
    }

    static let maxTaps = 3
    /// Pause after a tap: the scroll-to-top animation, and Mirroring tends to drop
    /// a gesture sent right after a tap.
    static let tapSettleUs: UInt32 = 600_000

    /// The status-bar clock, in window points. Measured on the iPhone Mirroring
    /// window: left of the Dynamic Island, in the status bar row.
    static func clockPoint(windowSize: CGSize) -> CGPoint {
        CGPoint(x: (windowSize.width * 0.176).rounded(), y: (windowSize.height * 0.08).rounded())
    }

    /// The probe: the finger moves down through the middle of the screen, which
    /// scrolls toward the top. At the top it only rubber-bands and settles back.
    static func probe(windowSize: CGSize) -> (from: CGPoint, to: CGPoint) {
        let x = windowSize.width / 2, mid = windowSize.height / 2, half = windowSize.height * 0.2
        return (CGPoint(x: x, y: mid - half), CGPoint(x: x, y: mid + half))
    }

    static func run(input: any InputProviding, capture: any ScreenCapturing, windowSize: CGSize,
                    settleTimeoutUs: UInt32 = EnvConfig.frameSettleTimeoutUs,
                    pause: (UInt32) -> Void = { usleep($0) }) -> Outcome {
        let before = capture.captureWithInfo().flatMap { GrayFrame(png: $0.data, size: $0.info.size) }
        let clock = clockPoint(windowSize: windowSize)
        let (from, to) = probe(windowSize: windowSize)
        for tap in 1 ... maxTaps {
            if let error = input.tap(x: clock.x, y: clock.y, cursorMode: nil) { return .failed(error) }
            pause(tapSettleUs)
            let probed = SwipeVerifier.run(capture: capture, distance: to.y - from.y,
                                           settleTimeoutUs: settleTimeoutUs) {
                input.swipe(fromX: from.x, fromY: from.y, toX: to.x, toY: to.y,
                            durationMs: EnvConfig.defaultSwipeDurationMs, cursorMode: nil)
            }
            switch probed {
            case .failed(let error):
                return .failed(error)
            case .unverified:
                return .done(atTop: false, taps: tap, effect: nil)
            case .verified(let effect, _) where !effect.moved:
                return .done(atTop: true, taps: tap, effect: overall(before, capture, settleTimeoutUs))
            case .verified:
                continue
            }
        }
        return .done(atTop: false, taps: maxTaps, effect: overall(before, capture, settleTimeoutUs))
    }

    /// The screen at the end compared with the screen before the first tap.
    private static func overall(_ before: GrayFrame?, _ capture: any ScreenCapturing,
                                _ settleTimeoutUs: UInt32) -> SwipeEffect? {
        guard let before,
              let shot = capture.captureSettledWithInfo(timeoutUs: settleTimeoutUs),
              let after = GrayFrame(png: shot.data, size: shot.info.size),
              after.width == before.width, after.height == before.height
        else { return nil }
        return SwipeMovement.effect(before: before, after: after, distance: 0)
    }

    /// The tool's result text (nil for `.failed`, which is an error).
    static func message(_ outcome: Outcome) -> String? {
        guard case .done(let atTop, let taps, let effect) = outcome else { return nil }
        guard let effect else {
            return "Tapped the status bar; not verified: the screen could not be captured."
        }
        guard atTop else {
            return "Not verified at the top: after \(taps) status-bar taps the list still scrolls up."
        }
        let checked = "At the top of the list (checked after \(taps) tap\(taps == 1 ? "" : "s"))"
        return effect.moved
            ? "\(checked); the screen moved (diff_ratio \(effect.diffRatio))."
            : "\(checked); it was already there."
    }
}
