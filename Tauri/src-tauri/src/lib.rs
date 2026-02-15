pub mod error;
pub mod events;
pub mod capture;
pub mod services;
pub mod state;
pub mod tray;
pub mod shortcuts;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_os::init())
        .setup(|app| {
            // Hide from dock — this is a menu bar (tray) app
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            // Set up system tray icon with menu
            tray::menu::setup_tray(app.handle())?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            capture::commands::capture_fullscreen,
            capture::commands::capture_area,
            capture::commands::capture_window,
            capture::commands::list_displays,
            capture::commands::list_windows,
            capture::commands::start_recording,
            capture::commands::stop_recording,
            capture::commands::cancel_recording,
            capture::commands::get_recording_state,
            services::storage::commands::get_history,
            services::storage::commands::delete_capture,
            services::storage::commands::toggle_favorite,
            services::storage::commands::get_storage_info,
            services::storage::commands::set_storage_location,
            services::ocr::commands::recognize_text,
            services::permissions::commands::check_screen_recording_permission,
            services::permissions::commands::check_microphone_permission,
            shortcuts::commands::set_shortcut_mode,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
