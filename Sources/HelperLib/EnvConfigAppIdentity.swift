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
// ABOUTME: EnvConfig properties naming the apps mirroir talks to and how it treats their windows:
// ABOUTME: bundle IDs, cursor-free input, the cover guard, auto-launch and handing focus back.

import Foundation

extension EnvConfig {

    public static var mirroringBundleID: String {
        readString("mirroringBundleID", envVar: "MIRROIR_BUNDLE_ID",
                   default: "com.apple.ScreenContinuity")
    }

    /// Bundle ID of the process that draws notification banners. Its
    /// display-sized overlay window over the target means a banner is up, so a
    /// click waits for it to clear instead of landing on the banner.
    public static var notificationCenterBundleID: String {
        readString("notificationCenterBundleID", envVar: "MIRROIR_NOTIFICATION_CENTER_BUNDLE_ID",
                   default: "com.apple.notificationcenterui")
    }

    /// Post mouse events directly to the target PID via `postToPid` instead
    /// of global HID posting. Works for regular macOS apps (e.g. FakeMirroring)
    /// but NOT for iPhone Mirroring — per-process injection does not register
    /// taps; only global HID events (`event.post(tap: .cghidEventTap)`) work,
    /// and those inherently move the system cursor. Enables local integration
    /// tests without cursor interference.
    public static var cursorFreeInput: Bool {
        readBool("cursorFreeInput", envVar: "MIRROIR_CURSOR_FREE", default: false)
    }

    /// Refuse pointing input when an accessibility hit-test says another app
    /// owns a point it would touch (see `InputSimulation.coverRefusal`).
    public static var coverGuard: Bool {
        readBool("coverGuard", envVar: "MIRROIR_COVER_GUARD", default: true)
    }

    /// Open iPhone Mirroring when a tool needs it and it isn't running or has no window
    /// (see `InputSimulation.openMirroringIfNeeded`).
    public static var autoLaunch: Bool {
        readBool("autoLaunch", envVar: "MIRROIR_AUTO_LAUNCH", default: true)
    }

    /// How long to wait for iPhone Mirroring's window after opening it.
    public static var autoLaunchTimeoutUs: UInt32 {
        readUInt32("autoLaunchTimeoutUs", default: 15_000_000)
    }

    /// Give focus back to the previous app once input to the mirror goes quiet
    /// (see `FocusRestorer`). On by default in this fork; upstream keeps the mirror frontmost.
    public static var restoreFocus: Bool {
        readBool("restoreFocus", envVar: "MIRROIR_RESTORE_FOCUS", default: true)
    }

    /// How long input must be quiet before focus is given back.
    public static var restoreFocusDelayUs: UInt32 {
        readUInt32("restoreFocusDelayUs", default: 3_000_000)
    }
}
