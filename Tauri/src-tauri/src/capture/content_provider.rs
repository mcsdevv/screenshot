use crate::capture::config::{DisplayInfo, WindowInfo};
use crate::error::CaptureError;

/// Cached wrapper around SCShareableContent
/// Caches content for 60 seconds to avoid repeated ScreenCaptureKit calls
pub struct ContentProvider {
    // TODO: Add SCShareableContent cache with TTL
}

impl ContentProvider {
    pub fn new() -> Self {
        Self {}
    }

    /// Preflight screen capture permissions
    pub async fn preflight(&self) -> Result<(), CaptureError> {
        // TODO: Call SCShareableContent.get() to trigger permission dialog
        Ok(())
    }

    /// Get all available displays
    pub async fn get_displays(&self) -> Result<Vec<DisplayInfo>, CaptureError> {
        // TODO: Query via SCShareableContent
        Ok(vec![DisplayInfo {
            id: 1,
            width: 2560,
            height: 1440,
            scale_factor: 2.0,
            is_primary: true,
        }])
    }

    /// Get all capturable windows
    pub async fn get_windows(&self) -> Result<Vec<WindowInfo>, CaptureError> {
        // TODO: Query via SCShareableContent, filter out small/own windows
        Ok(vec![])
    }
}
