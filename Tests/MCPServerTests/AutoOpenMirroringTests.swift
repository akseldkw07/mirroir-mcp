// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests opening iPhone Mirroring automatically and pressing Connect on its unlock screen.
// ABOUTME: The launcher and the click are stubs: unit tests never launch apps or post clicks.

import XCTest
import CoreGraphics
import HelperLib
@testable import mirroir_mcp

/// Launcher stub: records launches and, when `connects`, makes the bridge report `state`.
private final class StubLauncher: MirroringLaunching, @unchecked Sendable {
    let bridge: StubBridge
    var result = true
    var stateAfterLaunch: WindowState? = .connected
    private(set) var launches = 0

    init(bridge: StubBridge) { self.bridge = bridge }

    func launch() -> Bool {
        launches += 1
        if let state = stateAfterLaunch { bridge.state = state }
        return result
    }
}

private final class ClickRecorder: @unchecked Sendable {
    private(set) var points: [CGPoint] = []
    func record(_ point: CGPoint) { points.append(point) }
}

final class AutoOpenMirroringTests: XCTestCase {

    private var bridge: StubBridge!
    private var launcher: StubLauncher!
    private var clicks: ClickRecorder!
    private var describer: StubDescriber!

    override func setUp() {
        super.setUp()
        bridge = StubBridge()
        // Not running as a process: nothing on the test Mac is brought forward.
        bridge.processRunning = false
        // The stub's AX resume "works" by default; here no AX control exists (measured).
        bridge.pressResumeResult = false
        bridge.windowInfo = WindowInfo(windowID: 1, position: CGPoint(x: 100, y: 200),
                                       size: CGSize(width: 322, height: 702), pid: 1)
        launcher = StubLauncher(bridge: bridge)
        clicks = ClickRecorder()
        describer = StubDescriber()
    }

    private func input(launcher: (any MirroringLaunching)?) -> InputSimulation {
        let clicks = clicks!
        let recovery = MirroringRecovery(launcher: launcher, launchTimeoutUs: 50_000,
                                         click: { clicks.record($0) })
        return InputSimulation(bridge: bridge, keyboardLayout: .usQWERTY, pasteVerifier: describer,
                               pointOwner: TargetOwnsEveryPoint(), recovery: recovery)
    }

    private func unlockScreen() -> ScreenDescriber.DescribeResult {
        ScreenDescriber.DescribeResult(elements: [
            TapPoint(text: "Unlock Your iPhone", tapX: 161, tapY: 360, confidence: 0.95),
            TapPoint(text: "Follow the instructions on \"Aksel's 15 Pro Max\" to unlock",
                     tapX: 161, tapY: 400, confidence: 0.9),
            TapPoint(text: "Connect", tapX: 160, tapY: 468, confidence: 0.95),
        ], screenshotBase64: "")
    }

    // MARK: - Opening the app

    func testNotRunningIsOpenedThenConnected() {
        bridge.state = .notRunning
        XCTAssertNil(input(launcher: launcher).ensureConnected(tag: "tap"))
        XCTAssertEqual(launcher.launches, 1)
    }

    func testNoWindowIsOpenedToo() {
        bridge.state = .noWindow
        XCTAssertNil(input(launcher: launcher).ensureConnected(tag: "tap"))
        XCTAssertEqual(launcher.launches, 1)
    }

    func testPrepareTargetOpensMirroring() {
        // scroll_to_top and read_scrolling_list call this before they look up the window.
        bridge.state = .notRunning
        XCTAssertNil(input(launcher: launcher).prepareTarget(tag: "scroll_to_top"))
        XCTAssertEqual(launcher.launches, 1)
    }

    func testConnectedIsNotLaunched() {
        bridge.state = .connected
        XCTAssertNil(input(launcher: launcher).ensureConnected(tag: "tap"))
        XCTAssertEqual(launcher.launches, 0)
    }

    func testLaunchThatNeverShowsAWindowSaysSo() throws {
        bridge.state = .notRunning
        launcher.stateAfterLaunch = .noWindow
        let error = try XCTUnwrap(input(launcher: launcher).ensureConnected(tag: "tap"))
        XCTAssertTrue(error.contains("Opened iPhone Mirroring"), error)
        XCTAssertTrue(error.contains("no window"), error)
    }

    func testFailedLaunchSaysSo() throws {
        bridge.state = .notRunning
        launcher.result = false
        launcher.stateAfterLaunch = nil
        let error = try XCTUnwrap(input(launcher: launcher).ensureConnected(tag: "tap"))
        XCTAssertTrue(error.contains("Couldn't open iPhone Mirroring"), error)
    }

    func testAutoLaunchOffKeepsTheOriginalMessage() {
        bridge.state = .notRunning
        XCTAssertEqual(input(launcher: nil).ensureConnected(tag: "tap"),
                       "Target 'iphone' is not running. Launch iPhone Mirroring first.")
    }

    // MARK: - Unlock screen

    func testUnlockScreenPressesConnectAndAsksForTheUnlock() throws {
        bridge.state = .paused
        describer.describeResult = unlockScreen()
        let error = try XCTUnwrap(input(launcher: launcher).ensureConnected(tag: "tap"))
        XCTAssertEqual(clicks.points, [CGPoint(x: 260, y: 668)], "Connect, in screen points")
        XCTAssertTrue(error.contains("Unlock your iPhone"), error)
        XCTAssertTrue(error.contains("pressed Connect"), error)
    }

    func testUnlockScreenThatConnectsIsFine() {
        bridge.state = .paused
        bridge.connectsAt = Date().addingTimeInterval(0.2)  // connected by the time it's rechecked
        describer.describeResult = unlockScreen()
        XCTAssertNil(input(launcher: launcher).ensureConnected(tag: "tap"))
    }

    func testOtherPausedScreensAreNotClicked() {
        bridge.state = .paused
        describer.describeResult = ScreenDescriber.DescribeResult(elements: [
            TapPoint(text: "Connect", tapX: 160, tapY: 468, confidence: 0.95),
        ], screenshotBase64: "")
        let error = input(launcher: launcher).ensureConnected(tag: "tap")
        XCTAssertTrue(error?.hasPrefix("Target 'iphone' is paused.") ?? false, error ?? "nil")
        XCTAssertEqual(clicks.points, [])
    }

    func testFindsConnectOnlyUnderTheUnlockHeading() {
        let elements = unlockScreen().elements
        XCTAssertEqual(InputSimulation.unlockScreenConnect(in: elements)?.tapY, 468)
        XCTAssertNil(InputSimulation.unlockScreenConnect(in: Array(elements.suffix(1))))
        XCTAssertNil(InputSimulation.unlockScreenConnect(in: Array(elements.prefix(2))))
    }
}
