import XCTest
import Carbon.HIToolbox
@testable import ScreenCapture

final class KeyboardShortcutsTests: XCTestCase {

    // MARK: - Shortcut Enum Tests

    func testAllShortcutCasesExist() {
        let allCases = KeyboardShortcuts.Shortcut.allCases
        XCTAssertEqual(allCases.count, 11)
        XCTAssertTrue(allCases.contains(.captureArea))
        XCTAssertTrue(allCases.contains(.captureWindow))
        XCTAssertTrue(allCases.contains(.captureFullscreen))
        XCTAssertTrue(allCases.contains(.captureScrolling))
        XCTAssertTrue(allCases.contains(.recordScreen))
        XCTAssertTrue(allCases.contains(.recordWindow))
        XCTAssertTrue(allCases.contains(.recordGIF))
        XCTAssertTrue(allCases.contains(.allInOne))
        XCTAssertTrue(allCases.contains(.ocr))
        XCTAssertTrue(allCases.contains(.pinScreenshot))
        XCTAssertTrue(allCases.contains(.showKeyboardShortcuts))
    }

    func testShortcutRawValues() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureArea.rawValue, "captureArea")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureWindow.rawValue, "captureWindow")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureFullscreen.rawValue, "captureFullscreen")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureScrolling.rawValue, "captureScrolling")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordScreen.rawValue, "recordScreen")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordWindow.rawValue, "recordWindow")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordGIF.rawValue, "recordGIF")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allInOne.rawValue, "allInOne")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.ocr.rawValue, "ocr")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.pinScreenshot.rawValue, "pinScreenshot")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.showKeyboardShortcuts.rawValue, "showKeyboardShortcuts")
    }

    // MARK: - Default Key Code Tests

    func testDefaultKeyCodeForCaptureArea() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureArea.defaultKeyCode, UInt32(kVK_ANSI_4))
    }

    func testDefaultKeyCodeForCaptureWindow() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureWindow.defaultKeyCode, UInt32(kVK_ANSI_5))
    }

    func testDefaultKeyCodeForCaptureFullscreen() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureFullscreen.defaultKeyCode, UInt32(kVK_ANSI_3))
    }

    func testDefaultKeyCodeForCaptureScrolling() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureScrolling.defaultKeyCode, UInt32(kVK_ANSI_6))
    }

    func testDefaultKeyCodeForRecordScreen() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordScreen.defaultKeyCode, UInt32(kVK_ANSI_7))
    }

    func testDefaultKeyCodeForRecordWindow() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordWindow.defaultKeyCode, UInt32(kVK_ANSI_8))
    }

    func testDefaultKeyCodeForRecordGIF() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordGIF.defaultKeyCode, UInt32(kVK_ANSI_8))
    }

    func testDefaultKeyCodeForAllInOne() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allInOne.defaultKeyCode, UInt32(kVK_ANSI_A))
    }

    func testDefaultKeyCodeForOCR() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.ocr.defaultKeyCode, UInt32(kVK_ANSI_O))
    }

    func testDefaultKeyCodeForPinScreenshot() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.pinScreenshot.defaultKeyCode, UInt32(kVK_ANSI_P))
    }

    func testDefaultKeyCodeForShowKeyboardShortcuts() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.showKeyboardShortcuts.defaultKeyCode, UInt32(kVK_ANSI_Slash))
    }
    // MARK: - Modifiers Tests (Native Shortcuts)

    func testModifiersWithNativeShortcutsForCaptureShortcuts() {
        let expectedCmdShift = UInt32(cmdKey | shiftKey)

        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureArea.modifiers(useNativeShortcuts: true), expectedCmdShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureWindow.modifiers(useNativeShortcuts: true), expectedCmdShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureFullscreen.modifiers(useNativeShortcuts: true), expectedCmdShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureScrolling.modifiers(useNativeShortcuts: true), expectedCmdShift)
    }

    func testModifiersWithNativeShortcutsForRecordingShortcuts() {
        let expectedCmdShift = UInt32(cmdKey | shiftKey)
        let expectedShiftOption = UInt32(shiftKey | optionKey)

        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordScreen.modifiers(useNativeShortcuts: true), expectedCmdShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordWindow.modifiers(useNativeShortcuts: true), expectedShiftOption)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordGIF.modifiers(useNativeShortcuts: true), expectedCmdShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.ocr.modifiers(useNativeShortcuts: true), expectedCmdShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.pinScreenshot.modifiers(useNativeShortcuts: true), expectedCmdShift)
    }

    func testModifiersWithNativeShortcutsForAllInOne() {
        let expectedCmdShiftOption = UInt32(cmdKey | shiftKey | optionKey)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allInOne.modifiers(useNativeShortcuts: true), expectedCmdShiftOption)
    }

    func testModifiersWithNativeShortcutsForShowKeyboardShortcuts() {
        let expectedCmd = UInt32(cmdKey)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.showKeyboardShortcuts.modifiers(useNativeShortcuts: true), expectedCmd)
    }
    // MARK: - Modifiers Tests (Non-Native Shortcuts)

    func testModifiersWithoutNativeShortcutsForCaptureShortcuts() {
        let expectedCtrlShift = UInt32(controlKey | shiftKey)

        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureArea.modifiers(useNativeShortcuts: false), expectedCtrlShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureWindow.modifiers(useNativeShortcuts: false), expectedCtrlShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureFullscreen.modifiers(useNativeShortcuts: false), expectedCtrlShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureScrolling.modifiers(useNativeShortcuts: false), expectedCtrlShift)
    }

    func testModifiersWithoutNativeShortcutsForRecordingShortcuts() {
        let expectedCtrlShift = UInt32(controlKey | shiftKey)
        let expectedShiftOption = UInt32(shiftKey | optionKey)

        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordScreen.modifiers(useNativeShortcuts: false), expectedCtrlShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordWindow.modifiers(useNativeShortcuts: false), expectedShiftOption)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordGIF.modifiers(useNativeShortcuts: false), expectedCtrlShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.ocr.modifiers(useNativeShortcuts: false), expectedCtrlShift)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.pinScreenshot.modifiers(useNativeShortcuts: false), expectedCtrlShift)
    }

    func testModifiersWithoutNativeShortcutsForAllInOne() {
        let expectedCtrlShiftOption = UInt32(controlKey | shiftKey | optionKey)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allInOne.modifiers(useNativeShortcuts: false), expectedCtrlShiftOption)
    }

    func testModifiersWithoutNativeShortcutsForShowKeyboardShortcuts() {
        let expectedCmd = UInt32(cmdKey)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.showKeyboardShortcuts.modifiers(useNativeShortcuts: false), expectedCmd)
    }
    func testDefaultModifiersUsesNonNativeShortcuts() {
        // defaultModifiers should use the safe mode (Control+Shift)
        let expectedCtrlShift = UInt32(controlKey | shiftKey)
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureArea.defaultModifiers, expectedCtrlShift)
    }

    // MARK: - Display Name Tests

    func testDisplayNames() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureArea.displayName, "Capture Area")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureWindow.displayName, "Capture Window")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureFullscreen.displayName, "Capture Fullscreen")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureScrolling.displayName, "Scrolling Capture")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordScreen.displayName, "Record Screen")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordWindow.displayName, "Record Window")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordGIF.displayName, "Record GIF")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allInOne.displayName, "All-in-One Menu")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.ocr.displayName, "Capture Text (OCR)")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.pinScreenshot.displayName, "Pin Screenshot")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.showKeyboardShortcuts.displayName, "Keyboard Shortcuts")
    }

    // MARK: - Display Shortcut Tests (Native)

    func testDisplayShortcutsWithNativeMode() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureArea.displayShortcut(useNativeShortcuts: true), "⌘⇧4")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureWindow.displayShortcut(useNativeShortcuts: true), "⌘⇧5")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureFullscreen.displayShortcut(useNativeShortcuts: true), "⌘⇧3")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureScrolling.displayShortcut(useNativeShortcuts: true), "⌘⇧6")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordScreen.displayShortcut(useNativeShortcuts: true), "⌘⇧7")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordWindow.displayShortcut(useNativeShortcuts: true), "⌥⇧8")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordGIF.displayShortcut(useNativeShortcuts: true), "⌘⇧8")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allInOne.displayShortcut(useNativeShortcuts: true), "⌘⇧⌥A")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.ocr.displayShortcut(useNativeShortcuts: true), "⌘⇧O")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.pinScreenshot.displayShortcut(useNativeShortcuts: true), "⌘⇧P")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.showKeyboardShortcuts.displayShortcut(useNativeShortcuts: true), "⌘/")
    }

    // MARK: - Display Shortcut Tests (Non-Native)

    func testDisplayShortcutsWithNonNativeMode() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureArea.displayShortcut(useNativeShortcuts: false), "⌃⇧4")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureWindow.displayShortcut(useNativeShortcuts: false), "⌃⇧5")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureFullscreen.displayShortcut(useNativeShortcuts: false), "⌃⇧3")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.captureScrolling.displayShortcut(useNativeShortcuts: false), "⌃⇧6")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordScreen.displayShortcut(useNativeShortcuts: false), "⌃⇧7")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordWindow.displayShortcut(useNativeShortcuts: false), "⌥⇧8")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.recordGIF.displayShortcut(useNativeShortcuts: false), "⌃⇧8")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allInOne.displayShortcut(useNativeShortcuts: false), "⌃⇧⌥A")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.ocr.displayShortcut(useNativeShortcuts: false), "⌃⇧O")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.pinScreenshot.displayShortcut(useNativeShortcuts: false), "⌃⇧P")
        XCTAssertEqual(KeyboardShortcuts.Shortcut.showKeyboardShortcuts.displayShortcut(useNativeShortcuts: false), "⌘/")
    }

    // MARK: - Hot Key ID Tests

    func testHotKeyIDsAreUnique() {
        var ids = Set<UInt32>()
        for shortcut in KeyboardShortcuts.Shortcut.allCases {
            let id = shortcut.hotKeyID
            XCTAssertFalse(ids.contains(id), "Duplicate hotKeyID found: \(id)")
            ids.insert(id)
        }
    }

    func testHotKeyIDsAreSequential() {
        let allCases = KeyboardShortcuts.Shortcut.allCases
        for (index, shortcut) in allCases.enumerated() {
            XCTAssertEqual(shortcut.hotKeyID, UInt32(index + 1))
        }
    }

    func testHotKeyIDsStartAtOne() {
        XCTAssertEqual(KeyboardShortcuts.Shortcut.allCases.first?.hotKeyID, 1)
    }

    // MARK: - Modifier String Helper Tests

    func testModifierStringForControl() {
        let result = KeyboardShortcuts.modifierString(for: UInt32(controlKey))
        XCTAssertEqual(result, "Ctrl")
    }

    func testModifierStringForOption() {
        let result = KeyboardShortcuts.modifierString(for: UInt32(optionKey))
        XCTAssertEqual(result, "Opt")
    }

    func testModifierStringForShift() {
        let result = KeyboardShortcuts.modifierString(for: UInt32(shiftKey))
        XCTAssertEqual(result, "Shift")
    }

    func testModifierStringForCommand() {
        let result = KeyboardShortcuts.modifierString(for: UInt32(cmdKey))
        XCTAssertEqual(result, "Cmd")
    }

    func testModifierStringForCombinedModifiers() {
        let modifiers = UInt32(controlKey | shiftKey)
        let result = KeyboardShortcuts.modifierString(for: modifiers)
        XCTAssertEqual(result, "Ctrl+Shift")
    }

    func testModifierStringForAllModifiers() {
        let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let result = KeyboardShortcuts.modifierString(for: modifiers)
        XCTAssertEqual(result, "Ctrl+Opt+Shift+Cmd")
    }

    func testModifierStringForNoModifiers() {
        let result = KeyboardShortcuts.modifierString(for: 0)
        XCTAssertEqual(result, "")
    }

    // MARK: - Key String Helper Tests

    func testKeyStringForLetterKeys() {
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_A)), "A")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_S)), "S")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_D)), "D")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_F)), "F")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_O)), "O")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_P)), "P")
    }

    func testKeyStringForNumberKeys() {
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_0)), "0")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_1)), "1")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_2)), "2")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_3)), "3")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_4)), "4")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_5)), "5")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_6)), "6")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_7)), "7")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_8)), "8")
        XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(kVK_ANSI_9)), "9")
    }

    func testKeyStringForUnknownKey() {
        let unknownKeyCode: UInt32 = 999
        XCTAssertEqual(KeyboardShortcuts.keyString(for: unknownKeyCode), "?")
    }

    func testKeyStringForAllSupportedKeys() {
        // Test all letter keys that are supported
        let letterKeys: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"),
            (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"),
            (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"),
            (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"),
            (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"), (kVK_ANSI_U, "U"),
            (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z")
        ]

        for (keyCode, expected) in letterKeys {
            XCTAssertEqual(KeyboardShortcuts.keyString(for: UInt32(keyCode)), expected,
                           "Expected \(expected) for keyCode \(keyCode)")
        }
    }
}
