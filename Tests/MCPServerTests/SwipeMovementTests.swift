// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests swipe verification: frame diffs, released-overscroll nudges, and the retry policy.
// ABOUTME: A swipe reports whether the screen moved instead of an unverified "Swiped".

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import mirroir_mcp

final class SwipeMovementTests: XCTestCase {

    private let width = 40
    private let height = 100

    /// Horizontal stripes of pseudo-random shades: row r shows shade `r + offset`
    /// of the `seed` sequence, so a frame built with offset s is the list scrolled
    /// by s rows. Random shades (not an arithmetic progression) keep a shifted
    /// frame from lining up with the original by accident.
    private func stripes(offset: Int = 0, seed: UInt64 = 37) -> GrayFrame {
        var state = seed &* 0x9E37_79B9_7F4A_7C15
        var shades = [UInt8]()
        for _ in 0 ..< (height + 200) {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            shades.append(UInt8(truncatingIfNeeded: state >> 24))
        }
        var pixels = [UInt8]()
        for row in 0 ..< height {
            pixels += Array(repeating: shades[row + offset], count: width)
        }
        return GrayFrame(width: width, height: height, pixels: pixels)
    }

    private func png(_ frame: GrayFrame) throws -> Data {
        let space = CGColorSpaceCreateDeviceGray()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: frame.width, height: frame.height, bitsPerComponent: 8,
            bytesPerRow: frame.width, space: space,
            bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let buffer = try XCTUnwrap(context.data).bindMemory(
            to: UInt8.self, capacity: frame.pixels.count)
        for (i, value) in frame.pixels.enumerated() { buffer[i] = value }
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func capture(_ frames: [GrayFrame]) throws -> SequenceCapture {
        SequenceCapture(frames: try frames.map(png),
                        windowSize: CGSize(width: width, height: height))
    }

    // MARK: - Frame comparison

    func testDiffRatioOfIdenticalFramesIsZero() {
        XCTAssertEqual(SwipeMovement.diffRatio(stripes(), stripes()), 0)
    }

    func testDiffRatioOfUnrelatedFramesIsHigh() {
        XCTAssertGreaterThan(SwipeMovement.diffRatio(stripes(), stripes(seed: 91)), 0.5)
    }

    func testDiffRatioIgnoresTopRows() {
        var changed = stripes()
        var pixels = changed.pixels
        for i in 0 ..< (10 * width) { pixels[i] = pixels[i] &+ 128 }
        changed = GrayFrame(width: width, height: height, pixels: pixels)
        XCTAssertGreaterThan(SwipeMovement.diffRatio(stripes(), changed), 0)
        XCTAssertEqual(SwipeMovement.diffRatio(stripes(), changed, ignoreTop: 10), 0)
    }

    func testSmallShiftIsANudge() {
        XCTAssertTrue(SwipeMovement.isNudge(stripes(), stripes(offset: 3), maxShift: 5))
        XCTAssertTrue(SwipeMovement.isNudge(stripes(offset: 3), stripes(), maxShift: 5))
    }

    func testShiftBeyondMaxIsNotANudge() {
        XCTAssertFalse(SwipeMovement.isNudge(stripes(), stripes(offset: 20), maxShift: 5))
    }

    func testNewContentIsNotANudge() {
        XCTAssertFalse(SwipeMovement.isNudge(stripes(), stripes(seed: 91), maxShift: 5))
    }

    func testDecodesPNGToGray() throws {
        let frame = stripes()
        let decoded = try XCTUnwrap(GrayFrame(png: try png(frame),
                                              size: CGSize(width: width, height: height)))
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertLessThan(SwipeMovement.diffRatio(frame, decoded), 0.01)
    }

    // MARK: - Effect of one swipe

    func testScrollToNewContentMoved() {
        let effect = SwipeMovement.effect(before: stripes(), after: stripes(seed: 91),
                                          distance: 300)
        XCTAssertTrue(effect.moved)
    }

    func testUnchangedScreenDidNotMove() {
        let effect = SwipeMovement.effect(before: stripes(), after: stripes(), distance: 300)
        XCTAssertFalse(effect.moved)
        XCTAssertEqual(effect.diffRatio, 0)
    }

    func testReleasedOverscrollDidNotMove() {
        // A shift of a few rows is iOS letting go of a held overscroll.
        let effect = SwipeMovement.effect(before: stripes(), after: stripes(offset: 3),
                                          distance: 300)
        XCTAssertFalse(effect.moved)
        XCTAssertGreaterThan(effect.diffRatio, SwipeMovement.movedThreshold)
    }

    func testRealScrollOfTheSameListMoved() {
        let effect = SwipeMovement.effect(before: stripes(), after: stripes(offset: 60),
                                          distance: 300)
        XCTAssertTrue(effect.moved)
    }

    // MARK: - Verifier

    func testMovedOnFirstAttemptSwipesOnce() throws {
        var swipes = 0
        let outcome = SwipeVerifier.run(capture: try capture([stripes(), stripes(seed: 91)]),
                                        distance: 300) { swipes += 1; return nil }
        XCTAssertEqual(swipes, 1)
        guard case .verified(let effect, let attempts) = outcome else {
            return XCTFail("expected verified, got \(outcome)")
        }
        XCTAssertTrue(effect.moved)
        XCTAssertEqual(attempts, 1)
    }

    func testUnmovedSwipeIsRetriedOnce() throws {
        var swipes = 0
        let outcome = SwipeVerifier.run(capture: try capture([stripes()]), distance: 300) {
            swipes += 1; return nil
        }
        XCTAssertEqual(swipes, 2)
        guard case .verified(let effect, let attempts) = outcome else {
            return XCTFail("expected verified, got \(outcome)")
        }
        XCTAssertFalse(effect.moved)
        XCTAssertEqual(attempts, 2)
    }

    func testDroppedGestureThatMovesOnRetryReportsMoved() throws {
        // before, two settled frames of the unchanged screen, then the retry lands.
        let frames = [stripes(), stripes(), stripes(), stripes(seed: 91)]
        var swipes = 0
        let outcome = SwipeVerifier.run(capture: try capture(frames), distance: 300) {
            swipes += 1; return nil
        }
        XCTAssertEqual(swipes, 2)
        guard case .verified(let effect, 2) = outcome else {
            return XCTFail("expected verified after 2 attempts, got \(outcome)")
        }
        XCTAssertTrue(effect.moved)
    }

    func testSwipeErrorIsReturnedWithoutRetry() throws {
        var swipes = 0
        let outcome = SwipeVerifier.run(capture: try capture([stripes()]), distance: 300) {
            swipes += 1; return "covered"
        }
        XCTAssertEqual(swipes, 1)
        XCTAssertEqual(outcome, .failed("covered"))
    }

    // MARK: - Result text

    private let from = CGPoint(x: 100, y: 600)
    private let to = CGPoint(x: 100, y: 200)

    func testMessageForMovedSwipe() {
        let text = SwipeVerifier.message(
            .verified(SwipeEffect(moved: true, diffRatio: 0.31), attempts: 1), from: from, to: to)
        XCTAssertEqual(text, "Swiped from (100,600) to (100,200): the screen moved (diff_ratio 0.31).")
    }

    func testMessageForMoveOnRetry() {
        let text = SwipeVerifier.message(
            .verified(SwipeEffect(moved: true, diffRatio: 0.2), attempts: 2), from: from, to: to)
        XCTAssertEqual(text, "Swiped from (100,600) to (100,200): the screen moved on the second try "
            + "(diff_ratio 0.2); the first gesture was dropped.")
    }

    func testMessageForUnmovedSwipe() {
        let text = SwipeVerifier.message(
            .verified(SwipeEffect(moved: false, diffRatio: 0.0021), attempts: 2), from: from, to: to)
        XCTAssertEqual(text, "Swiped from (100,600) to (100,200): the screen did not change "
            + "(diff_ratio 0.0021), also on a retry. The list may be at its end, or the gesture was dropped.")
    }

    func testMessageForUnverifiedSwipe() {
        XCTAssertEqual(SwipeVerifier.message(.unverified, from: from, to: to),
                       "Swiped from (100,600) to (100,200); not verified: the screen could not be captured.")
    }

    func testNoCaptureMeansUnverified() {
        let capture = StubCapture()
        capture.captureResult = nil
        var swipes = 0
        let outcome = SwipeVerifier.run(capture: capture, distance: 300) {
            swipes += 1; return nil
        }
        XCTAssertEqual(swipes, 1)
        XCTAssertEqual(outcome, .unverified)
    }
}
