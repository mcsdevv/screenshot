use crate::capture::config::*;
use crate::capture::recording::RecordingSessionState;
use crate::error::CaptureError;
use crate::services::storage::manager::CaptureItem;

#[tauri::command]
pub async fn capture_fullscreen(
    display_id: Option<u32>,
    include_cursor: bool,
    format: ImageFormat,
) -> Result<CaptureItem, CaptureError> {
    let _data = crate::capture::screenshot::capture_fullscreen(display_id, include_cursor, &format).await?;
    // TODO: Save to storage, create CaptureItem
    Err(CaptureError::CaptureFailed("Not yet implemented".into()))
}

#[tauri::command]
pub async fn capture_area(
    rect: CaptureRect,
    display_id: u32,
    include_cursor: bool,
    format: ImageFormat,
) -> Result<CaptureItem, CaptureError> {
    let _data = crate::capture::screenshot::capture_area(&rect, display_id, include_cursor, &format).await?;
    Err(CaptureError::CaptureFailed("Not yet implemented".into()))
}

#[tauri::command]
pub async fn capture_window(
    window_id: u32,
    include_cursor: bool,
    format: ImageFormat,
) -> Result<CaptureItem, CaptureError> {
    let _data = crate::capture::screenshot::capture_window(window_id, include_cursor, &format).await?;
    Err(CaptureError::CaptureFailed("Not yet implemented".into()))
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
) -> Result<(), CaptureError> {
    crate::capture::recording::start_recording(target, config).await
}

#[tauri::command]
pub async fn stop_recording() -> Result<CaptureItem, CaptureError> {
    let _path = crate::capture::recording::stop_recording().await?;
    Err(CaptureError::RecordingFailed("Not yet implemented".into()))
}

#[tauri::command]
pub async fn cancel_recording() -> Result<(), CaptureError> {
    crate::capture::recording::cancel_recording().await
}

#[tauri::command]
pub fn get_recording_state() -> RecordingSessionState {
    crate::capture::recording::get_state()
}
