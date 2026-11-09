// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Addresses one window by ID: a SkyLight key-window record, and window fields stamped on posted events.
// ABOUTME: Swipes are built on it, so a swipe scrolls the mirror with the user's front app and cursor left where they are.

import CoreGraphics
import Foundation

/// Addresses events to one window through SkyLight. `focusKeys` posts a
/// mouse record with a blanked (all-ones) location through
/// `SLPSPostEventRecordTo`, the call the window server uses to hand a process
/// an event for one of its windows: it makes the window its app's key window
/// without a click and without making the app active. `stamp` sets an
/// event's window fields, so posting it to the window's process reaches that
/// window with the pointer elsewhere.
///
/// Measured on macOS 26.5 against iPhone Mirroring and FakeMirroring: taps,
/// double taps, long presses and keystrokes landed this way with another app
/// in front. On macOS 27 (measured 2026-11-08) only swipes still do: window
/// click records never reach the iPhone, even with the mirror in front, and
/// iPhone Mirroring forwards keys only while it is the active app. Taps are
/// HID clicks and key calls take the front and hand it back (`prepareKeyCall`).
final class SkyLightWindowPoster: WindowEventPosting, @unchecked Sendable {

    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias PostEventRecord =
        @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Int32

    /// The live poster, or nil when this macOS does not export the SkyLight
    /// and Process Manager entry points it calls.
    static let live: SkyLightWindowPoster? = SkyLightWindowPoster()

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let applicationServicesPath =
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"

    /// Byte layout of the window server's event record.
    private enum Record {
        static let size = 0xf8
        static let lengthOffset = 0x04
        static let typeOffset = 0x08
        static let windowLocationOffset = 0x20
        static let windowLocationLength = 0x10
        static let flagsOffset = 0x3a
        static let windowIDOffset = 0x3c
        static let mouseDown: UInt8 = 1
        static let mouseUp: UInt8 = 2
        /// Marks the record as addressed to the window in `windowIDOffset`.
        static let windowTargeted: UInt8 = 0x10
        static let blankedLocationByte: UInt8 = 0xff
    }

    /// Size of a Process Manager serial number (two UInt32).
    private static let processSerialNumberSize = 8

    private let processForPID: ProcessForPID
    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Int32
    /// Absent on a macOS without it; swipes then keep the HID path.
    private let setWindowLocation: SetWindowLocation?
    /// The event fields that name the window an event belongs to.
    private static let windowNumberFields = [51, 52, 91].compactMap { CGEventField(rawValue: $0) }
    private let postEventRecord: PostEventRecord

    private init?() {
        guard let skyLight = dlopen(Self.skyLightPath, RTLD_NOW),
              let services = dlopen(Self.applicationServicesPath, RTLD_NOW),
              let post = dlsym(skyLight, "SLPSPostEventRecordTo"),
              let psn = dlsym(services, "GetProcessForPID") else {
            DebugLog.log("skylight", "event-record entry points unavailable; window input disabled")
            return nil
        }
        setWindowLocation = dlsym(skyLight, "SLEventSetWindowLocation")
            .map { unsafeBitCast($0, to: SetWindowLocation.self) }
        postEventRecord = unsafeBitCast(post, to: PostEventRecord.self)
        processForPID = unsafeBitCast(psn, to: ProcessForPID.self)
    }

    func focusKeys(in window: WindowInfo) -> Bool {
        [Record.mouseDown, Record.mouseUp].allSatisfy { type in
            post(to: window) { record in
                record.storeBytes(of: type, toByteOffset: Record.typeOffset, as: UInt8.self)
                for offset in 0..<Record.windowLocationLength {
                    record.storeBytes(of: Record.blankedLocationByte,
                                      toByteOffset: Record.windowLocationOffset + offset, as: UInt8.self)
                }
            }
        }
    }

    var canStampEvents: Bool { setWindowLocation != nil }

    /// Without the window fields, a posted event finds no window and is dropped.
    /// Setting an event's location clears its window location, so that comes last.
    func stamp(_ event: CGEvent, at point: CGPoint, in window: WindowInfo) {
        event.location = CGPoint(x: window.position.x + point.x, y: window.position.y + point.y)
        for field in Self.windowNumberFields {
            event.setIntegerValueField(field, value: Int64(window.windowID))
        }
        _ = setWindowLocation?(event, point)
        event.timestamp = mach_absolute_time()
    }

    // MARK: - Private

    /// Build one record addressed to `window`, let `fill` set its event
    /// fields, and post it to the window's process.
    private func post(to window: WindowInfo, fill: (UnsafeMutableRawPointer) -> Void) -> Bool {
        let record = UnsafeMutableRawPointer.allocate(byteCount: Record.size, alignment: 8)
        defer { record.deallocate() }
        record.initializeMemory(as: UInt8.self, repeating: 0, count: Record.size)
        record.storeBytes(of: UInt8(Record.size), toByteOffset: Record.lengthOffset, as: UInt8.self)
        record.storeBytes(of: Record.windowTargeted, toByteOffset: Record.flagsOffset, as: UInt8.self)
        record.storeBytes(of: UInt32(window.windowID), toByteOffset: Record.windowIDOffset, as: UInt32.self)
        fill(record)

        let psn = UnsafeMutableRawPointer.allocate(byteCount: Self.processSerialNumberSize, alignment: 4)
        defer { psn.deallocate() }
        psn.initializeMemory(as: UInt8.self, repeating: 0, count: Self.processSerialNumberSize)
        guard processForPID(window.pid, psn) == noErr else {
            DebugLog.log("skylight", "no process serial number for pid \(window.pid)")
            return false
        }
        let status = postEventRecord(psn, record)
        if status != 0 { DebugLog.log("skylight", "post failed: \(status)") }
        return status == 0
    }
}
