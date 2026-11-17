/*
 * Copyright 2026 Async-IO.org
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not
 * use this file except in compliance with the License. You may obtain a copy of
 * the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License.
 */
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
        static let eventNumberOffset = 0x8a
        static let mouseDown: UInt8 = 1
        static let mouseUp: UInt8 = 2
        /// An AppKit-defined event; with `applicationActivated` in the
        /// event-number field it is the window server's "application
        /// activated" record.
        static let appKitDefined: UInt8 = 0x0d
        static let applicationActivated: Int16 = 0x01
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

    /// Makes the app AppKit-active, then its window key.
    func focusKeys(in window: WindowInfo) -> Bool {
        Self.focusKeyFills.allSatisfy { post(to: window, fill: $0) }
    }

    /// Fills one event record's fields.
    typealias RecordFill = @Sendable (UnsafeMutableRawPointer) -> Void

    /// The records `focusKeys` posts, in order. The app handles keys only
    /// while it believes it is active; the "application activated" record
    /// runs that without making it the front process, so the user's own
    /// typing stays in their app (without it, keys never reach an iOS 27
    /// phone). The blanked-location button pair then makes the window key
    /// without a click.
    static let focusKeyFills: [RecordFill] = [
        { record in
            record.storeBytes(of: Record.appKitDefined, toByteOffset: Record.typeOffset, as: UInt8.self)
            record.storeBytes(of: Record.applicationActivated,
                              toByteOffset: Record.eventNumberOffset, as: Int16.self)
        },
    ] + [Record.mouseDown, Record.mouseUp].map { type in
        { record in
            record.storeBytes(of: type, toByteOffset: Record.typeOffset, as: UInt8.self)
            for offset in 0..<Record.windowLocationLength {
                record.storeBytes(of: Record.blankedLocationByte,
                                  toByteOffset: Record.windowLocationOffset + offset, as: UInt8.self)
            }
        }
    }

    /// The bytes of one record addressed to `windowID`, with `fill` applied.
    static func record(windowID: CGWindowID, fill: RecordFill) -> [UInt8] {
        let record = UnsafeMutableRawPointer.allocate(byteCount: Record.size, alignment: 8)
        defer { record.deallocate() }
        record.initializeMemory(as: UInt8.self, repeating: 0, count: Record.size)
        record.storeBytes(of: UInt8(Record.size), toByteOffset: Record.lengthOffset, as: UInt8.self)
        record.storeBytes(of: Record.windowTargeted, toByteOffset: Record.flagsOffset, as: UInt8.self)
        record.storeBytes(of: UInt32(windowID), toByteOffset: Record.windowIDOffset, as: UInt32.self)
        fill(record)
        return Array(UnsafeBufferPointer(start: record.assumingMemoryBound(to: UInt8.self), count: Record.size))
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
    private func post(to window: WindowInfo, fill: RecordFill) -> Bool {
        var record = Self.record(windowID: window.windowID, fill: fill)

        let psn = UnsafeMutableRawPointer.allocate(byteCount: Self.processSerialNumberSize, alignment: 4)
        defer { psn.deallocate() }
        psn.initializeMemory(as: UInt8.self, repeating: 0, count: Self.processSerialNumberSize)
        guard processForPID(window.pid, psn) == noErr else {
            DebugLog.log("skylight", "no process serial number for pid \(window.pid)")
            return false
        }
        let status = record.withUnsafeMutableBytes { bytes -> Int32 in
            guard let base = bytes.baseAddress else { return -1 }
            return postEventRecord(psn, base)
        }
        if status != 0 { DebugLog.log("skylight", "post failed: \(status)") }
        return status == 0
    }
}
