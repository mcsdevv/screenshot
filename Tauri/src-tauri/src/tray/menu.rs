use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager};

/// Build and configure the system tray icon with menu
pub fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    // Menu items — Capture
    let capture_fullscreen =
        MenuItem::with_id(app, "capture_fullscreen", "Capture Fullscreen  ⌃⇧3", true, None::<&str>)?;
    let capture_area =
        MenuItem::with_id(app, "capture_area", "Capture Area            ⌃⇧4", true, None::<&str>)?;
    let capture_window =
        MenuItem::with_id(app, "capture_window", "Capture Window       ⌃⇧5", true, None::<&str>)?;

    let sep1 = PredefinedMenuItem::separator(app)?;

    // Utilities
    let open_folder =
        MenuItem::with_id(app, "open_folder", "Open Screenshots Folder", true, None::<&str>)?;
    let preferences =
        MenuItem::with_id(app, "preferences", "Preferences…", true, None::<&str>)?;

    let sep2 = PredefinedMenuItem::separator(app)?;

    let quit = MenuItem::with_id(app, "quit", "Quit ScreenCapture", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[
        &capture_fullscreen,
        &capture_area,
        &capture_window,
        &sep1,
        &open_folder,
        &preferences,
        &sep2,
        &quit,
    ])?;

    // Load tray icon from embedded PNG bytes
    let icon_bytes = include_bytes!("../../icons/tray-icon.png");
    let icon = tauri::image::Image::from_bytes(icon_bytes)?;

    let _tray = TrayIconBuilder::new()
        .icon(icon)
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(true)
        .tooltip("ScreenCapture")
        .on_menu_event(move |app, event| {
            match event.id().as_ref() {
                "quit" => {
                    app.exit(0);
                }
                "preferences" => {
                    open_settings_window(app);
                }
                "open_folder" => {
                    let state: tauri::State<'_, crate::state::app_state::AppState> = app.state();
                    let storage = state.storage.lock().unwrap();
                    let path = storage.screenshots_dir();
                    drop(storage);
                    let _ = std::fs::create_dir_all(&path);
                    let _ = std::process::Command::new("open").arg(&path).spawn();
                }
                "capture_fullscreen" => {
                    let app_handle = app.clone();
                    tauri::async_runtime::spawn(async move {
                        do_tray_capture_fullscreen(&app_handle).await;
                    });
                }
                "capture_area" => {
                    open_selection_window(app, "selection", "/selection");
                }
                "capture_window" => {
                    open_selection_window(app, "window-picker", "/selection?mode=window");
                }
                _ => {}
            }
        })
        .build(app)?;

    Ok(())
}

/// Open (or focus) the settings window at /settings route
fn open_settings_window(app: &AppHandle) {
    // If settings window already exists, just show and focus it
    if let Some(window) = app.get_webview_window("settings") {
        let _ = window.show();
        let _ = window.set_focus();
        return;
    }

    // Create a new settings window
    let url = tauri::WebviewUrl::App("/settings".into());
    match tauri::WebviewWindowBuilder::new(app, "settings", url)
        .title("ScreenCapture Preferences")
        .inner_size(600.0, 500.0)
        .resizable(true)
        .center()
        .build()
    {
        Ok(_) => {}
        Err(e) => {
            eprintln!("Failed to open settings window: {e}");
        }
    }
}

/// Perform fullscreen capture triggered from tray menu
async fn do_tray_capture_fullscreen(app: &AppHandle) {
    use crate::capture::config::ImageFormat;
    use crate::capture::screenshot;
    use crate::services::storage::manager::CaptureType;
    use crate::state::app_state::AppState;

    let format = ImageFormat::Png;
    let data = match screenshot::capture_fullscreen(None, false, &format).await {
        Ok(d) => d,
        Err(e) => {
            log::error!("Tray capture failed: {}", e);
            return;
        }
    };

    let state: tauri::State<'_, AppState> = app.state();
    let mut storage = state.storage.lock().unwrap();
    let filename = storage.generate_filename(&CaptureType::Screenshot, "png");
    let dir = storage.screenshots_dir();
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join(&filename);
    if let Err(e) = std::fs::write(&path, &data) {
        log::error!("Failed to save screenshot: {}", e);
        return;
    }
    let item = crate::services::storage::manager::CaptureItem::new_screenshot(filename);
    storage.history.add(item.clone());
    let _ = storage.save_history();
    drop(storage);

    // Emit capture completed event so frontend can show quick-access overlay
    let _ = app.emit("capture:completed", &item);
}

/// Open a fullscreen transparent selection window
fn open_selection_window(app: &AppHandle, label: &str, path: &str) {
    if let Some(window) = app.get_webview_window(label) {
        let _ = window.show();
        let _ = window.set_focus();
        return;
    }
    let url = tauri::WebviewUrl::App(path.into());
    let _ = tauri::WebviewWindowBuilder::new(app, label, url)
        .fullscreen(true)
        .decorations(false)
        .always_on_top(true)
        .build();
}

/// Update tray icon for recording state
pub fn set_recording_icon(_app: &AppHandle, _is_recording: bool) {
    // TODO: Swap between normal icon and red recording indicator
}
