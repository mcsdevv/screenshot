import AppKit
import Carbon.HIToolbox

class KeyboardShortcuts {
    enum Shortcut: String, CaseIterable {
        case captureArea = "captureArea"
        case captureWindow = "captureWindow"
        case captureFullscreen = "captureFullscreen"
        case captureScrolling = "captureScrolling"
        case recordScreen = "recordScreen"
        case recordGIF = "recordGIF"
        case allInOne = "allInOne"
        case ocr = "ocr"
        case pinScreenshot = "pinScreenshot"

        var defaultKeyCode: UInt32 {
            switch self {
            case .captureArea: return UInt32(kVK_ANSI_4)
            case .captureWindow: return UInt32(kVK_ANSI_5)
            case .captureFullscreen: return UInt32(kVK_ANSI_3)
            case .captureScrolling: return UInt32(kVK_ANSI_6)
            case .recordScreen: return UInt32(kVK_ANSI_7)
            case .recordGIF: return UInt32(kVK_ANSI_8)
            case .allInOne: return UInt32(kVK_ANSI_A)
            case .ocr: return UInt32(kVK_ANSI_O)
            case .pinScreenshot: return UInt32(kVK_ANSI_P)
            }
        }

        /// Returns the modifiers based on whether native shortcuts are remapped
        func modifiers(useNativeShortcuts: Bool) -> UInt32 {
            if useNativeShortcuts {
                // Use Cmd+Shift when native macOS shortcuts are disabled
                switch self {
                case .captureArea, .captureWindow, .captureFullscreen:
                    return UInt32(cmdKey | shiftKey)
                case .captureScrolling:
                    return UInt32(cmdKey | shiftKey)
                case .recordScreen, .recordGIF, .ocr, .pinScreenshot:
                    return UInt32(cmdKey | shiftKey)
                case .allInOne:
                    return UInt32(cmdKey | shiftKey | optionKey)
                }
            } else {
                // Use Control+Shift to avoid conflicts with macOS built-in ⌘⇧3/4/5
                switch self {
                case .captureArea, .captureWindow, .captureFullscreen, .captureScrolling:
                    return UInt32(controlKey | shiftKey)
                case .recordScreen, .recordGIF, .ocr, .pinScreenshot:
                    return UInt32(controlKey | shiftKey)
                case .allInOne:
                    return UInt32(controlKey | shiftKey | optionKey)
                }
            }
        }

        var defaultModifiers: UInt32 {
            // Default to Control+Shift (safe mode)
            return modifiers(useNativeShortcuts: false)
        }

        var displayName: String {
            switch self {
            case .captureArea: return "Capture Area"
            case .captureWindow: return "Capture Window"
            case .captureFullscreen: return "Capture Fullscreen"
            case .captureScrolling: return "Scrolling Capture"
            case .recordScreen: return "Record Screen"
            case .recordGIF: return "Record GIF"
            case .allInOne: return "All-in-One Menu"
            case .ocr: return "Capture Text (OCR)"
            case .pinScreenshot: return "Pin Screenshot"
            }
        }

        /// Returns the display shortcut string based on whether native shortcuts are remapped
        func displayShortcut(useNativeShortcuts: Bool) -> String {
            if useNativeShortcuts {
                switch self {
                case .captureArea: return "⌘⇧4"
                case .captureWindow: return "⌘⇧5"
                case .captureFullscreen: return "⌘⇧3"
                case .captureScrolling: return "⌘⇧6"
                case .recordScreen: return "⌘⇧7"
                case .recordGIF: return "⌘⇧8"
                case .allInOne: return "⌘⇧⌥A"
                case .ocr: return "⌘⇧O"
                case .pinScreenshot: return "⌘⇧P"
                }
            } else {
                switch self {
                case .captureArea: return "⌃⇧4"
                case .captureWindow: return "⌃⇧5"
                case .captureFullscreen: return "⌃⇧3"
                case .captureScrolling: return "⌃⇧6"
                case .recordScreen: return "⌃⇧7"
                case .recordGIF: return "⌃⇧8"
                case .allInOne: return "⌃⇧⌥A"
                case .ocr: return "⌃⇧O"
                case .pinScreenshot: return "⌃⇧P"
                }
            }
        }

        var hotKeyID: UInt32 {
            guard let index = Shortcut.allCases.firstIndex(of: self) else { return 0 }
            return UInt32(index + 1)
        }
    }

    private static let hotKeySignature: OSType = {
        let chars: [UInt8] = [0x53, 0x43, 0x41, 0x50] // "SCAP"
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }()

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [Shortcut: EventHotKeyRef] = [:]
    private var callbacks: [Shortcut: () -> Void] = [:]

    /// Whether we're using native macOS shortcut keys (Cmd+Shift) or fallback (Ctrl+Shift)
    private(set) var useNativeShortcuts: Bool = false

    private static var sharedInstance: KeyboardShortcuts?

    init() {
        KeyboardShortcuts.sharedInstance = self
        // Check if native shortcuts have been remapped
        useNativeShortcuts = SystemShortcutManager.shared.shortcutsRemapped
        setupEventHandler()
    }

    /// Register a shortcut with appropriate modifiers based on native shortcut state
    func register(shortcut: Shortcut, callback: @escaping () -> Void) {
        callbacks[shortcut] = callback
        registerHotKey(shortcut: shortcut)
    }

    /// Internal method to register hotkey with current modifier settings
    private func registerHotKey(shortcut: Shortcut) {
        // Unregister first if already registered
        if let ref = hotKeyRefs[shortcut] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: shortcut)
        }

        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = KeyboardShortcuts.hotKeySignature
        hotKeyID.id = shortcut.hotKeyID

        let modifiers = shortcut.modifiers(useNativeShortcuts: useNativeShortcuts)
        let displayStr = shortcut.displayShortcut(useNativeShortcuts: useNativeShortcuts)

        let status = RegisterEventHotKey(
            shortcut.defaultKeyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[shortcut] = ref
            debugLog("KeyboardShortcuts: Registered \(shortcut.displayName) (\(displayStr))")
        } else {
            errorLog("KeyboardShortcuts: Failed to register \(shortcut.displayName), status: \(status)")
        }
    }

    /// Re-register all shortcuts with updated modifiers (called when native shortcuts are remapped)
    func reregisterAllShortcuts(useNativeShortcuts: Bool) {
        debugLog("KeyboardShortcuts: Re-registering shortcuts with useNativeShortcuts=\(useNativeShortcuts)")
        self.useNativeShortcuts = useNativeShortcuts

        // Re-register all shortcuts with callbacks
        for shortcut in Shortcut.allCases where callbacks[shortcut] != nil {
            registerHotKey(shortcut: shortcut)
        }
    }

    func unregister(shortcut: Shortcut) {
        if let ref = hotKeyRefs[shortcut] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: shortcut)
        }
        callbacks.removeValue(forKey: shortcut)
    }

    func unregisterAll() {
        for (shortcut, _) in hotKeyRefs {
            unregister(shortcut: shortcut)
        }
    }

    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            debugLog("KeyboardShortcuts: Hot key event received, id: \(hotKeyID.id), status: \(status)")

            if let shortcuts = KeyboardShortcuts.sharedInstance {
                for shortcut in Shortcut.allCases {
                    if shortcut.hotKeyID == hotKeyID.id {
                        debugLog("KeyboardShortcuts: Triggering \(shortcut.displayName)")
                        DispatchQueue.main.async {
                            shortcuts.callbacks[shortcut]?()
                        }
                        break
                    }
                }
            } else {
                errorLog("KeyboardShortcuts: sharedInstance is nil!")
            }

            return noErr
        }

        let installStatus = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandlerRef)
        if installStatus == noErr {
            debugLog("KeyboardShortcuts: Event handler installed successfully")
        } else {
            errorLog("KeyboardShortcuts: Failed to install event handler, status: \(installStatus)")
        }
    }

    deinit {
        unregisterAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}

extension KeyboardShortcuts {
    static func modifierString(for modifiers: UInt32) -> String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Ctrl")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Opt")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Cmd")
        }

        return parts.joined(separator: "+")
    }

    static func keyString(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        default: return "?"
        }
    }
}
