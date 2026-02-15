use crate::capture::config::*;
use crate::capture::recording::RecordingSessionState;
use crate::error::CaptureError;
use crate::state::app_state::AppState;
use crate::services::storage::manager::{CaptureItem, CaptureType};

fn format_extension(format: &ImageFormat) -> &'static str {
    match format {
        ImageFormat::Png => "png",
        ImageFormat::Jpeg { .. } => "jpg",
        ImageFormat::Tiff => "tiff",
    }
}

fn save_screenshot(
    data: &[u8],
    format: &ImageFormat,
    state: &tauri::State<'_, AppState>,
) -> Result<CaptureItem, CaptureError> {
    let mut storage = state.storage.lock().unwrap();
    let ext = format_extension(format);
    let filename = storage.generate_filename(&CaptureType::Screenshot, ext);
    let dir = storage.screenshots_dir();
    std::fs::create_dir_all(&dir)?;
    let path = dir.join(&filename);
    std::fs::write(&path, data)?;

    let item = CaptureItem::new_screenshot(filename);
    storage.history.add(item.clone());
    storage.save_history()?;
    Ok(item)
}

#[tauri::command]
pub async fn capture_fullscreen(
    display_id: Option<u32>,
    include_cursor: bool,
    format: ImageFormat,
    state: tauri::State<'_, AppState>,
) -> Result<CaptureItem, CaptureError> {
    let data = crate::capture::screenshot::capture_fullscreen(display_id, include_cursor, &format).await?;
    save_screenshot(&data, &format, &state)
}

#[tauri::command]
pub async fn capture_area(
    rect: CaptureRect,
    display_id: u32,
    include_cursor: bool,
    format: ImageFormat,
    state: tauri::State<'_, AppState>,
) -> Result<CaptureItem, CaptureError> {
    let data = crate::capture::screenshot::capture_area(&rect, display_id, include_cursor, &format).await?;
    save_screenshot(&data, &format, &state)
}

#[tauri::command]
pub async fn capture_window(
    window_id: u32,
    include_cursor: bool,
    format: ImageFormat,
    state: tauri::State<'_, AppState>,
) -> Result<CaptureItem, CaptureError> {
    let data = crate::capture::screenshot::capture_window(window_id, include_cursor, &format).await?;
    save_screenshot(&data, &format, &state)
}

#[tauri::command]
pub async fn list_displays() -> Result<Vec<DisplayInfo>, CaptureError> {
    let provider = crate::capture::content_provider::ContentProvider::new();
    provider.get_displays().await
}

#[tauri::command]
pub async fn list_windows() -> Result<Vec<WindowInfo>, CaptureError> {
    let provider = crate::capture::content_provider::ContentProvider::new();
    provider.get_windows().await
}

#[tauri::command]
pub async fn start_recording(
    target: RecordingTarget,
    config: RecordingConfig,
    state: tauri::State<'_, AppState>,
) -> Result<(), CaptureError> {
    crate::capture::recording::start_recording(target, config, &state).await
}

#[tauri::command]
pub async fn stop_recording(
    state: tauri::State<'_, AppState>,
) -> Result<CaptureItem, CaptureError> {
    crate::capture::recording::stop_recording(&state).await
}

#[tauri::command]
pub async fn cancel_recording(
    state: tauri::State<'_, AppState>,
) -> Result<(), CaptureError> {
    crate::capture::recording::cancel_recording(&state).await
}

#[tauri::command]
pub fn get_recording_state(
    state: tauri::State<'_, AppState>,
) -> RecordingSessionState {
    crate::capture::recording::get_state(&state)
}
