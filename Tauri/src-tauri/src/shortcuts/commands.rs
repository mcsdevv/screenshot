use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use tauri::Emitter;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ShortcutMode {
    Safe,   // Ctrl+Shift prefix (default, avoids macOS conflicts)
    Native, // Cmd+Shift prefix (requires disabling macOS Screenshot.app shortcuts)
}

/// Register default shortcuts during app setup
pub fn register_default_shortcuts(app: &tauri::AppHandle) {
    if let Err(e) = register_shortcuts(app, &ShortcutMode::Safe) {
        log::warn!("Failed to register default shortcuts: {}", e);
    }
}

#[tauri::command]
pub fn set_shortcut_mode(mode: ShortcutMode, app: tauri::AppHandle) -> Result<(), String> {
    // Unregister all existing shortcuts
    let manager = app.global_shortcut();
    let _ = manager.unregister_all();

    register_shortcuts(&app, &mode)
}

fn register_shortcuts(app: &tauri::AppHandle, mode: &ShortcutMode) -> Result<(), String> {
    let modifier = match mode {
        ShortcutMode::Safe => "ctrl+shift",
        ShortcutMode::Native => "super+shift",
    };

    let shortcuts = vec![
        (format!("{}+3", modifier), "capture_fullscreen"),
        (format!("{}+4", modifier), "capture_area"),
        (format!("{}+5", modifier), "capture_window"),
        (format!("{}+7", modifier), "record_area"),
        (format!("{}+9", modifier), "record_fullscreen"),
    ];

    let manager = app.global_shortcut();

    for (combo, action) in shortcuts {
        let shortcut: tauri_plugin_global_shortcut::Shortcut = combo
            .parse()
            .map_err(|e| format!("Invalid shortcut '{}': {:?}", combo, e))?;
        let action_name = action.to_string();
        let app_clone = app.clone();
        manager
            .on_shortcut(shortcut, move |_app, _shortcut, event| {
                if event.state == ShortcutState::Pressed {
                    let mut payload = HashMap::new();
                    payload.insert("action", action_name.clone());
                    let _ = app_clone.emit("shortcut:triggered", &payload);
                }
            })
            .map_err(|e| format!("Failed to register shortcut: {}", e))?;
    }

    Ok(())
}
