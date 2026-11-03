// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests scroll_to_top: status-bar taps verified by an upward probe swipe, up to three taps.
// ABOUTME: Frames come from SequenceCapture with settling off, so each capture call is one frame.

import XCTest
import HelperLib
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import mirroir_mcp

final class ScrollToTopTests: XCTestCase {

    private let size = CGSize(width: 40, height: 100)
    private var input: StubInput!

    override func setUp() {
        super.setUp()
        input = StubInput()
    }

    /// A frame of pseudo-random row shades; different seeds are unrelated screens.
    private func frame(_ seed: UInt64) throws -> Data {
        let w = Int(size.width), h = Int(size.height)
        var state = (seed + 1) &* 0x9E37_79B9_7F4A_7C15
        var pixels = [UInt8]()
        for _ in 0 ..< h {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            pixels += Array(repeating: UInt8(truncatingIfNeeded: state >> 24), count: w)
        }
        let context = try XCTUnwrap(CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let buffer = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: w * h)
        for (i, value) in pixels.enumerated() { buffer[i] = value }
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func run(_ seeds: [UInt64]) throws -> ScrollToTop.Outcome {
        let capture = SequenceCapture(frames: try seeds.map(frame), windowSize: size)
        return ScrollToTop.run(input: input, capture: capture, windowSize: size,
                               settleTimeoutUs: 0, pause: { _ in })
    }

    func testTapsTheStatusBarClock() {
        XCTAssertEqual(ScrollToTop.clockPoint(windowSize: CGSize(width: 334, height: 724)),
                       CGPoint(x: 59, y: 58))
    }

    func testProbeSwipesTheFingerDownTowardTheTop() {
        let probe = ScrollToTop.probe(windowSize: CGSize(width: 400, height: 1000))
        XCTAssertEqual(probe.from, CGPoint(x: 200, y: 300))
        XCTAssertEqual(probe.to, CGPoint(x: 200, y: 700))
    }

    func testAlreadyAtTopAfterOneTap() throws {
        // Every frame is the same screen: the probe (and its retry) can't move it.
        let outcome = try run([1])
        XCTAssertEqual(outcome, .done(atTop: true, taps: 1, effect: SwipeEffect(moved: false, diffRatio: 0)))
        XCTAssertEqual(input.tapCalls.count, 1)
        XCTAssertEqual(input.swipeCalls.count, 2)
    }

    func testLostTapIsRetried() throws {
        // before, probe-before, probe moved (the first tap was lost), then still.
        let outcome = try run([1, 1, 2])
        guard case .done(let atTop, let taps, let effect) = outcome else {
            return XCTFail("expected done, got \(outcome)")
        }
        XCTAssertTrue(atTop)
        XCTAssertEqual(taps, 2)
        XCTAssertEqual(effect?.moved, true)
        XCTAssertEqual(input.tapCalls.count, 2)
    }

    func testGivesUpAfterThreeTaps() throws {
        // A new screen on every capture: the probe always moves.
        let outcome = try run(Array(1 ... 20))
        guard case .done(let atTop, let taps, _) = outcome else {
            return XCTFail("expected done, got \(outcome)")
        }
        XCTAssertFalse(atTop)
        XCTAssertEqual(taps, 3)
        XCTAssertEqual(input.tapCalls.count, 3)
    }

    func testTapErrorStopsWithoutSwiping() throws {
        input.tapResult = "covered"
        XCTAssertEqual(try run([1]), .failed("covered"))
        XCTAssertTrue(input.swipeCalls.isEmpty)
    }

    func testNoCaptureIsUnverified() {
        let capture = StubCapture()
        capture.captureResult = nil
        let outcome = ScrollToTop.run(input: input, capture: capture, windowSize: size,
                                      settleTimeoutUs: 0, pause: { _ in })
        XCTAssertEqual(outcome, .done(atTop: false, taps: 1, effect: nil))
    }

    func testToolIsRegisteredAndReportsUnverifiedWithoutCapture() {
        let server = MCPServer(policy: PermissionPolicy(skipPermissions: true, config: nil))
        let capture = StubCapture()
        capture.captureResult = nil
        MirroirMCP.registerScrollToTopTool(
            server: server, registry: makeTestRegistry(bridge: StubBridge(), input: input, capture: capture))
        let response = server.handleRequest(JSONRPCRequest(
            jsonrpc: "2.0", id: .number(1), method: "tools/call",
            params: .object(["name": .string("scroll_to_top"), "arguments": .object([:])])))
        guard case .object(let result) = response?.result,
              case .array(let content) = result["content"],
              case .object(let first) = content.first,
              case .string(let text) = first["text"] else {
            return XCTFail("no text result: \(String(describing: response))")
        }
        XCTAssertEqual(text, "Tapped the status bar; not verified: the screen could not be captured.")
        XCTAssertEqual(input.tapCalls.count, 1)
    }

    func testMessages() {
        XCTAssertEqual(
            ScrollToTop.message(.done(atTop: true, taps: 1, effect: SwipeEffect(moved: true, diffRatio: 0.4))),
            "At the top of the list (checked after 1 tap); the screen moved (diff_ratio 0.4).")
        XCTAssertEqual(
            ScrollToTop.message(.done(atTop: true, taps: 2, effect: SwipeEffect(moved: false, diffRatio: 0))),
            "At the top of the list (checked after 2 taps); it was already there.")
        XCTAssertEqual(
            ScrollToTop.message(.done(atTop: false, taps: 3, effect: SwipeEffect(moved: true, diffRatio: 0.3))),
            "Not verified at the top: after 3 status-bar taps the list still scrolls up.")
        XCTAssertEqual(
            ScrollToTop.message(.done(atTop: false, taps: 1, effect: nil)),
            "Tapped the status bar; not verified: the screen could not be captured.")
        XCTAssertNil(ScrollToTop.message(.failed("covered")))
    }
}
