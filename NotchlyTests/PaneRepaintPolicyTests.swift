import XCTest

final class PaneRepaintPolicyTests: XCTestCase {
    func testNonKeyVisiblePanePaints() {
        XCTAssertTrue(PaneRepaintPolicy.shouldPaint(
            windowExists: true, windowIsKey: false, windowIsVisible: true, paneRevealed: true
        ))
    }

    func testKeyWindowSkipsForcedRepaint() {
        XCTAssertFalse(PaneRepaintPolicy.shouldPaint(
            windowExists: true, windowIsKey: true, windowIsVisible: true, paneRevealed: true
        ))
    }

    func testHiddenPanelSkipsPaint() {
        XCTAssertFalse(PaneRepaintPolicy.shouldPaint(
            windowExists: true, windowIsKey: false, windowIsVisible: false, paneRevealed: true
        ))
    }

    func testMissingWindowSkipsPaint() {
        XCTAssertFalse(PaneRepaintPolicy.shouldPaint(
            windowExists: false, windowIsKey: false, windowIsVisible: false, paneRevealed: true
        ))
    }

    func testInitializingPaneSkipsPaint() {
        XCTAssertFalse(PaneRepaintPolicy.shouldPaint(
            windowExists: true, windowIsKey: false, windowIsVisible: true, paneRevealed: false
        ))
    }
}
