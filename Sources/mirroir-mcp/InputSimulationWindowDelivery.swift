// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Chooses between posting input to the target's window directly and the HID path that brings it to the front.
// ABOUTME: Taps and escape clicks go to the window when a poster can address it; keys borrow the front, then return it.

import CoreGraphics
import Foundation

extension InputSimulation {

    /// The poster that can deliver to `info`'s window directly, or nil when
    /// input to it goes through the HID path: no window poster is configured,
    /// or the window server gave no window ID to address.
    func windowDelivery(for info: WindowInfo) -> (any WindowEventPosting)? {
        guard let windowPoster, info.windowID != 0, info.pid > 0 else { return nil }
        return windowPoster
    }

    /// Keyboard preamble for type_text, press_key and shake. iPhone Mirroring
    /// forwards keys to the phone only while it is the active app: on macOS 27
    /// (measured 2026-11-08), keys posted to its process with another app in
    /// front never reached the phone, however they were addressed. So a key
    /// call brings the target to the front through `prepareKeyboardInput` and
    /// its keys go through the HID tap; the caller finishes the returned
    /// handback once its keys are sent, which gives the user's app the front back.
    func prepareKeyCall(tag: String) -> (handback: FrontHandback, error: String?) {
        let handback = beginFrontHandback()
        return (handback, prepareKeyboardInput(tag: tag))
    }

    /// The click the session-escape plugins free a paused session with, at a
    /// screen point. It goes to the window by record when the window can be
    /// addressed, so freeing the session does not take the front either;
    /// otherwise it is a HID click.
    func escapeClick() -> (CGPoint) -> Void {
        let pid = cursorFreePID
        return { [self] point in
            if let info = bridge.getWindowInfo(), let poster = windowDelivery(for: info) {
                let local = CGPoint(x: point.x - info.position.x, y: point.y - info.position.y)
                _ = poster.click(at: local, holdUs: CGEventInput.clickHoldUs, in: info)
            } else {
                _ = CGEventInput.click(at: point, targetPID: pid)
            }
        }
    }
}
