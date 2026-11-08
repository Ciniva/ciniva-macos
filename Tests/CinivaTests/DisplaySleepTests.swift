@testable import Ciniva
import IOKit.pwr_mgt
import XCTest

final class DisplaySleepTests: XCTestCase {
    private func heldByUs() -> Bool {
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&out) == kIOReturnSuccess, let byPid = out?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let mine = byPid[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []
        return mine.contains { ($0[kIOPMAssertionNameKey] as? String) == "Ciniva is playing video" }
    }

    func testAssertionFollowsState() {
        let blocker = DisplaySleepBlocker()
        XCTAssertFalse(heldByUs())
        blocker.set(true)
        XCTAssertTrue(blocker.isHeld)
        XCTAssertTrue(heldByUs())
        blocker.set(true)
        blocker.set(false)
        XCTAssertFalse(blocker.isHeld)
        XCTAssertFalse(heldByUs())
    }
}
