// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests which input InputSimulation posts straight to the target's window and which keeps the HID path.
// ABOUTME: Pins swipes to the window poster with no activation; taps, keys, drags and HID swipes need the front.

import CoreGraphics
import XCTest
@testable import mirroir_mcp

final class WindowDeliveryTests: XCTestCase {

    private let windowID: CGWindowID = 4242
    private let windowPID: pid_t = 777

    /// A connected target that is NOT front and is not a running process:
    /// any input that needed activation would be refused, and nothing on the
    /// Mac running the tests is brought forward.
    private func makeInput(
        poster: RecordingWindowPoster?, keys: RecordingKeyPoster = RecordingKeyPoster(),
        clicks: RecordingClickPoster = RecordingClickPoster(), windowID: CGWindowID? = nil
    ) -> InputSimulation {
        let bridge = StubBridge()
        bridge.processRunning = false
        bridge.frontmost = false
        bridge.windowInfo = WindowInfo(
            windowID: windowID ?? self.windowID, position: CGPoint(x: 100, y: 50),
            size: CGSize(width: 410, height: 898), pid: windowPID)
        return InputSimulation(bridge: bridge, keyboardLayout: .usQWERTY,
                               keyPoster: keys, clickPoster: clicks, windowPoster: poster)
    }

    // MARK: - Pointing

    /// The click that frees a paused session is a real HID click at the screen
    /// point: a window-addressed one never reaches the iPhone on macOS 27.
    func testTheEscapeClickIsAHIDClickEvenWithAWindowPoster() {
        let poster = RecordingWindowPoster()
        let clicks = RecordingClickPoster()
        makeInput(poster: poster, clicks: clicks).escapeClick()(CGPoint(x: 300, y: 400))
        XCTAssertTrue(poster.keyFocusWindows.isEmpty)
        XCTAssertEqual(clicks.clicks.map(\.point), [CGPoint(x: 300, y: 400)])
    }

    /// Window-addressed clicks never reached the iPhone on macOS 27 (measured
    /// 2026-11-08, mirror in front or not), so a tap takes the HID path, which
    /// needs the front: refused here, with nothing posted and no window record.
    func testWithAWindowPosterATapStillNeedsTheFront() {
        let poster = RecordingWindowPoster()
        let clicks = RecordingClickPoster()
        XCTAssertNotNil(makeInput(poster: poster, clicks: clicks).tap(x: 200, y: 300, cursorMode: nil))
        XCTAssertTrue(clicks.clicks.isEmpty)
        XCTAssertTrue(poster.keyFocusWindows.isEmpty)
    }

    func testWithAWindowPosterADoubleTapStillNeedsTheFront() {
        let poster = RecordingWindowPoster()
        let clicks = RecordingClickPoster()
        XCTAssertNotNil(makeInput(poster: poster, clicks: clicks).doubleTap(x: 10, y: 20, cursorMode: nil))
        XCTAssertTrue(clicks.clicks.isEmpty)
        XCTAssertTrue(poster.keyFocusWindows.isEmpty)
    }

    func testWithAWindowPosterALongPressStillNeedsTheFront() {
        let poster = RecordingWindowPoster()
        let clicks = RecordingClickPoster()
        XCTAssertNotNil(makeInput(poster: poster, clicks: clicks)
            .longPress(x: 10, y: 20, durationMs: 800, cursorMode: nil))
        XCTAssertTrue(clicks.clicks.isEmpty)
        XCTAssertTrue(poster.keyFocusWindows.isEmpty)
    }

    func testWithoutAWindowPosterATapNeedsTheFront() {
        let message = makeInput(poster: nil).tap(x: 200, y: 300, cursorMode: nil)
        XCTAssertNotNil(message, "the HID path refuses a target it cannot bring to the front")
    }

    func testAWindowTheWindowServerDidNotNameKeepsTheHIDPath() {
        let poster = RecordingWindowPoster()
        let message = makeInput(poster: poster, windowID: 0)
            .swipe(fromX: 200, fromY: 600, toX: 200, toY: 200, durationMs: 100, cursorMode: nil)
        XCTAssertNotNil(message)
        XCTAssertTrue(poster.stampedPoints.isEmpty, "no window ID, nothing to address")
    }

    /// Drag events and records lose their intermediate points on macOS 26: a
    /// drag stays on the HID path, which needs the front. Refused here, and the
    /// window poster is never used.
    func testADragNeverUsesTheWindowPoster() {
        let poster = RecordingWindowPoster()
        let input = makeInput(poster: poster)
        XCTAssertNotNil(input.drag(fromX: 200, fromY: 600, toX: 200, toY: 200,
                                   durationMs: 300, cursorMode: nil))
        XCTAssertTrue(poster.stampedPoints.isEmpty)
        XCTAssertTrue(poster.keyFocusWindows.isEmpty)
    }

    /// A swipe is scroll events: addressed to the window, they scroll it with
    /// the mirror covered and another app in front (measured on an XR, macOS 26.5).
    /// The window's PID here is one no process has, so the events go nowhere.
    func testASwipeGoesToTheWindowWithoutActivatingTheTarget() {
        let poster = RecordingWindowPoster()
        let bridge = StubBridge()
        bridge.processRunning = false
        bridge.frontmost = false
        bridge.windowInfo = WindowInfo(windowID: windowID, position: CGPoint(x: 100, y: 50),
                                       size: CGSize(width: 410, height: 898), pid: 99_999)
        let input = InputSimulation(bridge: bridge, keyboardLayout: .usQWERTY,
                                    keyPoster: RecordingKeyPoster(), windowPoster: poster)
        XCTAssertNil(input.swipe(fromX: 200, fromY: 600, toX: 200, toY: 200,
                                 durationMs: 100, cursorMode: nil))
        XCTAssertEqual(poster.keyFocusWindows, [windowID], "one focus record for the gesture")
        XCTAssertFalse(poster.stampedPoints.isEmpty)
        XCTAssertEqual(Set(poster.stampedPoints.map(\.x)), [200])
        XCTAssertEqual(Set(poster.stampedPoints.map(\.y)), [400], "every event at the midpoint")
    }

    func testWithoutEventStampingASwipeNeedsTheFront() {
        let poster = RecordingWindowPoster()
        poster.canStampEvents = false
        XCTAssertNotNil(makeInput(poster: poster).swipe(fromX: 200, fromY: 600, toX: 200, toY: 200,
                                                        durationMs: 100, cursorMode: nil))
        XCTAssertTrue(poster.stampedPoints.isEmpty)
    }

    // MARK: - Keys

    /// iPhone Mirroring forwards keys only while it is the active app, so a
    /// window poster does not spare keys the front (see FrontHandbackTests for
    /// the front being returned afterwards).
    func testWithAWindowPosterKeysStillNeedTheFront() {
        let poster = RecordingWindowPoster()
        let keys = RecordingKeyPoster()
        let result = makeInput(poster: poster, keys: keys).pressKey(keyName: "return", modifiers: [])
        XCTAssertFalse(result.success, "the HID path refuses a target it cannot bring to the front")
        XCTAssertTrue(keys.targets.isEmpty)
        XCTAssertTrue(poster.keyFocusWindows.isEmpty, "no key focus record is posted for keys")
    }

    func testWithoutAWindowPosterKeysNeedTheFront() {
        let keys = RecordingKeyPoster()
        let result = makeInput(poster: nil, keys: keys).pressKey(keyName: "return", modifiers: [])
        XCTAssertFalse(result.success, "the HID path refuses a target it cannot bring to the front")
        XCTAssertTrue(keys.targets.isEmpty)
    }

    // MARK: - Live entry points

    func testTheSkyLightEntryPointsResolveOnThisMac() {
        XCTAssertNotNil(SkyLightWindowPoster.live,
                        "SLPSPostEventRecordTo and GetProcessForPID must resolve on supported macOS")
    }

    /// `test`, `compile` and `record` build their input through this factory,
    /// so the CLI posts to the window exactly like the MCP server does.
    func testEveryMirrorEntryPointGetsTheWindowPoster() {
        XCTAssertNotNil(IPhoneMirroringTarget.input(bridge: MirroringBridge()).windowPoster)
    }
}
