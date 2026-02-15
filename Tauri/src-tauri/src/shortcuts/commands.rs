use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ShortcutMode {
    Safe,   // Ctrl+Shift prefix (default, avoids macOS conflicts)
    Native, // Cmd+Shift prefix (requires disabling macOS Screenshot.app shortcuts)
}

#[tauri::command]
pub fn set_shortcut_mode(_mode: ShortcutMode) -> Result<(), String> {
    // TODO: Unregister all shortcuts, re-register with new modifier
    // Safe mode: Ctrl+Shift+{key}
    // Native mode: Cmd+Shift+{key}
    //
    // Shortcuts to register:
    // 1. Capture Area: +4
    // 2. Capture Window: +5
    // 3. Capture Fullscreen: +3
    // 4. Record Area: +7
    // 5. Record Window: Opt+Shift+8 (always)
    // 6. Record Fullscreen: +9
    // 7. All-in-One Menu: +Opt+A
    // 8. OCR: +O
    // 9. Pin Screenshot: +P
    // 10. Open Screenshots: +S
    // 11. Show Shortcuts: Cmd+/ (always)
    Ok(())
}
