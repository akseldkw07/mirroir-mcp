// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Swipe verification: compares captures from before and after a swipe and retries a dropped one.
// ABOUTME: Ignores the status bar and treats a few-pixel shift (a released overscroll) as no movement.

import CoreGraphics
import Foundation
import HelperLib
import ImageIO

/// An 8-bit grayscale frame, row-major from the top-left.
struct GrayFrame: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count must be width x height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Decode a PNG and scale it to `size` (the window's size in points), so frames
    /// from Retina and non-Retina displays compare row for row.
    init?(png: Data, size: CGSize) {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: w * h)
        self.init(width: w, height: h, pixels: Array(UnsafeBufferPointer(start: buffer, count: w * h)))
    }

    /// Rows `range` of this frame.
    func rows(_ range: Range<Int>) -> GrayFrame {
        let start = range.lowerBound * width, end = range.upperBound * width
        return GrayFrame(width: width, height: range.count, pixels: Array(pixels[start ..< end]))
    }
}

/// Whether one swipe moved the screen.
struct SwipeEffect: Equatable, Sendable {
    let moved: Bool
    /// Share of pixels (below the status bar) that changed.
    let diffRatio: Double
}

/// Frame comparison for swipes (pure transformations).
enum SwipeMovement {
    /// Share of changed pixels that counts as movement. A scroll indicator
    /// flashing on its own is ~0.003; a scroll of a few rows is 0.2+.
    static let movedThreshold = 0.01
    /// Grey-level difference above which a pixel counts as changed.
    static let pixelThreshold = 24
    /// Largest shift (points) still treated as a released overscroll.
    static let nudgeMaxShift = 40
    /// A released overscroll rests between pixels, so even lined up a few
    /// percent of pixels differ; new content differs by ~30%.
    static let nudgeMatch = 0.08

    /// Share of pixels that changed between `a` and `b`, below the top `ignoreTop` rows.
    static func diffRatio(_ a: GrayFrame, _ b: GrayFrame, ignoreTop: Int = 0) -> Double {
        guard a.width == b.width, a.height == b.height else { return 1 }
        let start = min(ignoreTop, a.height) * a.width
        let count = a.pixels.count - start
        guard count > 0 else { return 0 }
        var changed = 0
        for i in start ..< a.pixels.count where abs(Int(a.pixels[i]) - Int(b.pixels[i])) > pixelThreshold {
            changed += 1
        }
        return Double(changed) / Double(count)
    }

    /// Whether `b` is `a` shifted vertically by at most `maxShift` rows.
    static func isNudge(_ a: GrayFrame, _ b: GrayFrame, maxShift: Int) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        let h = a.height
        let limit = min(maxShift, h - 1)
        guard limit >= 1 else { return false }
        for shift in 1 ... limit {
            if diffRatio(a.rows(0 ..< h - shift), b.rows(shift ..< h)) < nudgeMatch { return true }
            if diffRatio(a.rows(shift ..< h), b.rows(0 ..< h - shift)) < nudgeMatch { return true }
        }
        return false
    }

    /// The effect of a swipe of `distance` points, from frames before and after it.
    /// The top tenth (the iOS status bar, whose clock ticks) is ignored.
    static func effect(before: GrayFrame, after: GrayFrame, distance: Double) -> SwipeEffect {
        let top = before.height / 10
        let ratio = diffRatio(before, after, ignoreTop: top)
        let maxShift = min(nudgeMaxShift, Int(distance) / 5)
        let nudge = ratio >= movedThreshold && maxShift > 0 && isNudge(
            before.rows(top ..< before.height), after.rows(top ..< after.height),
            maxShift: maxShift)
        let rounded = (ratio * 10_000).rounded() / 10_000
        return SwipeEffect(moved: ratio >= movedThreshold && !nudge, diffRatio: rounded)
    }
}

/// Runs a swipe and reports whether it moved the screen.
enum SwipeVerifier {
    enum Outcome: Equatable {
        /// The swipe was refused or failed; nothing to verify.
        case failed(String)
        /// The swipe ran but the screen couldn't be captured to check it.
        case unverified
        /// The swipe ran `attempts` times (a dropped gesture is retried once).
        case verified(SwipeEffect, attempts: Int)
    }

    /// iPhone Mirroring drops about 1 synthesized gesture in 10, so a swipe that
    /// didn't move is tried once more; a real end of list fails both times.
    static func run(capture: any ScreenCapturing, distance: Double,
                    settleTimeoutUs: UInt32 = EnvConfig.frameSettleTimeoutUs,
                    perform: () -> String?) -> Outcome {
        var before = capture.captureWithInfo().flatMap { GrayFrame(png: $0.data, size: $0.info.size) }
        for attempt in 1 ... 2 {
            if let error = perform() { return .failed(error) }
            guard let start = before,
                  let shot = capture.captureSettledWithInfo(timeoutUs: settleTimeoutUs),
                  let after = GrayFrame(png: shot.data, size: shot.info.size),
                  after.width == start.width, after.height == start.height
            else { return .unverified }
            let effect = SwipeMovement.effect(before: start, after: after, distance: distance)
            if effect.moved || attempt == 2 { return .verified(effect, attempts: attempt) }
            before = after
        }
        return .unverified
    }

    /// The tool's result text for `outcome` (nil for `.failed`, which is an error).
    /// Starts with "Swiped from" so callers matching the old text keep working.
    static func message(_ outcome: Outcome, from: CGPoint, to: CGPoint) -> String? {
        let swiped = "Swiped from (\(Int(from.x)),\(Int(from.y))) to (\(Int(to.x)),\(Int(to.y)))"
        switch outcome {
        case .failed:
            return nil
        case .unverified:
            return "\(swiped); not verified: the screen could not be captured."
        case .verified(let effect, let attempts):
            let ratio = "diff_ratio \(effect.diffRatio)"
            if effect.moved, attempts == 1 {
                return "\(swiped): the screen moved (\(ratio))."
            }
            if effect.moved {
                return "\(swiped): the screen moved on the second try (\(ratio)); "
                    + "the first gesture was dropped."
            }
            return "\(swiped): the screen did not change (\(ratio)), also on a retry. "
                + "The list may be at its end, or the gesture was dropped."
        }
    }
}
