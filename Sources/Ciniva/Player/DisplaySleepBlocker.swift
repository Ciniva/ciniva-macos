import Foundation
import IOKit.pwr_mgt

/// Keeps the display awake while video plays; mpv's own stop-screensaver doesn't apply when it renders into our view.
final class DisplaySleepBlocker {
    private var assertion: IOPMAssertionID = 0
    private(set) var isHeld = false

    func set(_ on: Bool) {
        guard on != isHeld else { return }
        if on {
            let reason = "Ciniva is playing video" as CFString
            isHeld = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertion
            ) == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertion)
            isHeld = false
        }
    }

    deinit {
        if isHeld { IOPMAssertionRelease(assertion) }
    }
}
