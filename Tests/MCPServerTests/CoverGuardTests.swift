// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests the cover guard: pointing input is refused when another app owns an input point.
// ABOUTME: Window captures show the target even when covered, but posted input lands on whatever is on top.

import XCTest
import CoreGraphics
import HelperLib
@testable import mirroir_mcp

/// Answers which process owns each screen point from a fixed table.
private final class StubPointOwner: PointOwnerLocating, @unchecked Sendable {
    var owners: [(point: CGPoint, owner: PointOwner)] = []
    var fallback: PointOwner?
    var windowOwner: String?
    private(set) var asked: [CGPoint] = []

    func topWindowOwnerName(at point: CGPoint, excluding pid: pid_t) -> String? { windowOwner }

    func owner(at point: CGPoint) -> PointOwner? {
        asked.append(point)
        return owners.first { $0.point == point }?.owner ?? fallback
    }
}

final class CoverGuardTests: XCTestCase {

    private let window = WindowInfo(windowID: 1, position: CGPoint(x: 100, y: 200),
                                    size: CGSize(width: 410, height: 898), pid: 42)
    private var owner: StubPointOwner!
    private var input: InputSimulation!

    override func setUp() {
        super.setUp()
        owner = StubPointOwner()
        input = InputSimulation(bridge: StubBridge(), keyboardLayout: .usQWERTY,
                                pointOwner: owner)
    }

    func testPointOwnedByTargetPasses() {
        owner.fallback = PointOwner(pid: 42, name: "iPhone Mirroring")
        XCTAssertNil(input.coverRefusal(screenPoints: [CGPoint(x: 300, y: 600)],
                                        info: window, tag: "tap"))
    }

    func testPointOwnedByAnotherAppRefusesAndNamesIt() throws {
        owner.fallback = PointOwner(pid: 7, name: "Finder")
        let error = try XCTUnwrap(input.coverRefusal(
            screenPoints: [CGPoint(x: 300, y: 600)], info: window, tag: "tap"))
        XCTAssertTrue(error.contains("Finder"), error)
        XCTAssertTrue(error.contains("(300, 600)"), error)
        XCTAssertTrue(error.contains("nothing was sent"), error)
    }

    func testUnknownOwnerRefuses() throws {
        owner.fallback = nil
        let error = try XCTUnwrap(input.coverRefusal(
            screenPoints: [CGPoint(x: 300, y: 600)], info: window, tag: "tap"))
        XCTAssertTrue(error.contains("could not tell"), error)
        XCTAssertFalse(error.contains("topmost window"), error)
    }

    func testUnknownOwnerNamesTheTopmostWindowWhenThereIsOne() throws {
        // Measured: a floating panel from a process without accessibility support
        // makes the hit-test fail; the window list still knows whose window it is.
        owner.fallback = nil
        owner.windowOwner = "osascript"
        let error = try XCTUnwrap(input.coverRefusal(
            screenPoints: [CGPoint(x: 300, y: 600)], info: window, tag: "tap"))
        XCTAssertTrue(error.contains("could not tell"), error)
        XCTAssertTrue(error.contains("the topmost window there belongs to osascript"), error)
    }

    func testAnyCoveredPointRefuses() throws {
        owner.fallback = PointOwner(pid: 42, name: "iPhone Mirroring")
        owner.owners = [(CGPoint(x: 300, y: 900), PointOwner(pid: 9, name: "Notification Center"))]
        let points = [CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 600), CGPoint(x: 300, y: 900)]
        let error = try XCTUnwrap(input.coverRefusal(screenPoints: points, info: window,
                                                     tag: "swipe"))
        XCTAssertTrue(error.contains("Notification Center"), error)
    }

    func testOwnerWithoutNameStillRefuses() throws {
        owner.fallback = PointOwner(pid: 9, name: nil)
        let error = try XCTUnwrap(input.coverRefusal(
            screenPoints: [CGPoint(x: 300, y: 600)], info: window, tag: "tap"))
        XCTAssertTrue(error.contains("pid 9"), error)
    }

    func testEveryPointIsChecked() {
        owner.fallback = PointOwner(pid: 42, name: "iPhone Mirroring")
        let points = [CGPoint(x: 150, y: 250), CGPoint(x: 200, y: 300), CGPoint(x: 250, y: 350)]
        XCTAssertNil(input.coverRefusal(screenPoints: points, info: window, tag: "swipe"))
        XCTAssertEqual(owner.asked, points)
    }

    func testSwipeCoveredOnlyAtItsEndIsRefused() throws {
        // The HID swipe path lands wherever the pointer is, so a path covered
        // past its start must be refused like a covered tap. The stub bridge's
        // window (pid 1) sits at the screen origin.
        owner.fallback = PointOwner(pid: 1, name: "iPhone Mirroring")
        owner.owners = [(CGPoint(x: 10, y: 10), PointOwner(pid: 7, name: "Finder"))]
        let error = try XCTUnwrap(input.swipe(fromX: 10, fromY: 12, toX: 10, toY: 10))
        XCTAssertTrue(error.contains("Finder"), error)
        XCTAssertTrue(error.contains("nothing was sent"), error)
    }

    func testSwipeChecksStartMidpointAndEnd() {
        // Scroll events go to the window under the cursor at the midpoint;
        // a swipe's start and end are checked too.
        let points = InputSimulation.swipeInputPoints(
            from: CGPoint(x: 100, y: 800), to: CGPoint(x: 100, y: 200))
        XCTAssertEqual(points, [CGPoint(x: 100, y: 800), CGPoint(x: 100, y: 500),
                                CGPoint(x: 100, y: 200)])
    }
}
