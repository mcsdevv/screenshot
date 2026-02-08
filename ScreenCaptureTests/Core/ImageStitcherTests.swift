import XCTest
@testable import ScreenCapture

final class ImageStitcherTests: XCTestCase {

    func testCaptureTypeListExcludesLegacyScrollingType() {
        XCTAssertEqual(CaptureType.allCases.count, 3)
        XCTAssertFalse(CaptureType.allCases.map(\.rawValue).contains("Scrolling"))
    }

    func testShortcutListExcludesLegacyScrollingShortcut() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allCases.count, 11)
        XCTAssertFalse(KeyboardShortcuts.Shortcut.allCases.map(\.rawValue).contains("captureScrolling"))
    }
}
