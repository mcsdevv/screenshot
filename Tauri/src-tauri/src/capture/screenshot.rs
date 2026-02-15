use crate::capture::config::{CaptureRect, ImageFormat};
use crate::error::CaptureError;

/// Capture a fullscreen screenshot
pub async fn capture_fullscreen(
    _display_id: Option<u32>,
    _include_cursor: bool,
    _format: &ImageFormat,
) -> Result<Vec<u8>, CaptureError> {
    // TODO: Implement via ScreenCaptureKit FFI
    // 1. Get display via SCShareableContent
    // 2. Create SCContentFilter for display
    // 3. Configure SCStreamConfiguration (resolution: best, cursor, scale)
    // 4. Call SCScreenshotManager.captureImage
    // 5. Encode to requested format
    Err(CaptureError::CaptureFailed("Not yet implemented".into()))
}

/// Capture a rectangular area
pub async fn capture_area(
    _rect: &CaptureRect,
    _display_id: u32,
    _include_cursor: bool,
    _format: &ImageFormat,
) -> Result<Vec<u8>, CaptureError> {
    // TODO: Implement via ScreenCaptureKit with sourceRect
    Err(CaptureError::CaptureFailed("Not yet implemented".into()))
}

/// Capture a specific window
pub async fn capture_window(
    _window_id: u32,
    _include_cursor: bool,
    _format: &ImageFormat,
) -> Result<Vec<u8>, CaptureError> {
    // TODO: Implement via ScreenCaptureKit with window filter
    Err(CaptureError::CaptureFailed("Not yet implemented".into()))
}
