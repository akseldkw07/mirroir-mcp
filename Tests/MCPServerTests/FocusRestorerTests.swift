// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests giving focus back to the previous app once input to the mirror goes quiet.
// ABOUTME: The focus calls and the timer are stubs: nothing on the test Mac changes focus.

import XCTest
import HelperLib
@testable import mirroir_mcp

/// Records activations and answers which app is front; never touches real focus.
private final class StubFocus: FocusSwitching, @unchecked Sendable {
    var front: pid_t?
    private(set) var activated: [pid_t] = []

    func frontmostPID() -> pid_t? { front }
    func activate(pid: pid_t) -> Bool {
        activated.append(pid)
        front = pid
        return true
    }
}

/// Holds scheduled restores so a test fires them by hand.
private final class ManualTimer: @unchecked Sendable {
    private(set) var pending: [@Sendable () -> Void] = []
    private(set) var delays: [UInt32] = []
    func schedule(_ delayUs: UInt32, _ work: @escaping @Sendable () -> Void) {
        delays.append(delayUs)
        pending.append(work)
    }
    func fireAll() {
        let work = pending
        pending = []
        work.forEach { $0() }
    }
}

private final class BusyFlag: @unchecked Sendable {
    var value = false
}

final class FocusRestorerTests: XCTestCase {

    private let target: pid_t = 100
    private let safari: pid_t = 200
    private let mail: pid_t = 300
    private var focus: StubFocus!
    private var timer: ManualTimer!
    private var restorer: FocusRestorer!
    private var busy = BusyFlag()

    override func setUp() {
        super.setUp()
        focus = StubFocus()
        timer = ManualTimer()
        let timer = timer!
        busy = BusyFlag()
        let busy = busy
        restorer = FocusRestorer(focus: focus, delayUs: 2_000_000,
                                 schedule: { timer.schedule($0, $1) },
                                 isBusy: { busy.value })
    }

    func testGivesFocusBackOnceInputGoesQuiet() {
        restorer.willActivate(target: target, previous: safari)
        focus.front = target
        XCTAssertEqual(timer.delays, [2_000_000])
        timer.fireAll()
        XCTAssertEqual(focus.activated, [safari])
    }

    func testMoreInputPostponesTheRestore() {
        restorer.willActivate(target: target, previous: safari)
        focus.front = target
        restorer.noteInput()
        restorer.noteInput()
        timer.fireAll()
        XCTAssertEqual(focus.activated, [safari], "only the last scheduled restore acts")
    }

    func testLeavesFocusAloneWhenTheUserMovedOn() {
        restorer.willActivate(target: target, previous: safari)
        focus.front = mail  // the user switched to Mail before the restore fired
        timer.fireAll()
        XCTAssertEqual(focus.activated, [])
    }

    func testNothingToRestoreWithoutAnotherApp() {
        restorer.willActivate(target: target, previous: nil)
        restorer.willActivate(target: target, previous: target)
        XCTAssertEqual(timer.delays, [])
    }

    func testInputWithoutASwitchSchedulesNothing() {
        restorer.noteInput()
        XCTAssertEqual(timer.delays, [])
    }

    func testRestoresOnlyOnce() {
        restorer.willActivate(target: target, previous: safari)
        focus.front = target
        timer.fireAll()
        restorer.noteInput()
        timer.fireAll()
        XCTAssertEqual(focus.activated, [safari])
    }

    func testANewSwitchRestoresTheLatestPreviousApp() {
        restorer.willActivate(target: target, previous: safari)
        restorer.willActivate(target: target, previous: mail)
        focus.front = target
        timer.fireAll()
        XCTAssertEqual(focus.activated, [mail])
    }

    func testWaitsForTheRunningToolCallToFinish() {
        // A long type_text can outlast the delay; its keys must not go to Safari.
        restorer.willActivate(target: target, previous: safari)
        focus.front = target
        busy.value = true
        timer.fireAll()
        XCTAssertEqual(focus.activated, [])
        XCTAssertEqual(timer.pending.count, 1, "tries again after another quiet period")
        busy.value = false
        timer.fireAll()
        XCTAssertEqual(focus.activated, [safari])
    }

    func testToolCallActivityCountsNestedCalls() {
        let activity = ToolCallActivity()
        XCTAssertFalse(activity.isBusy)
        activity.begin()
        activity.begin()
        activity.end()
        XCTAssertTrue(activity.isBusy)
        activity.end()
        XCTAssertFalse(activity.isBusy)
    }

    func testOffByDefault() {
        XCTAssertFalse(EnvConfig.restoreFocus)
    }
}
