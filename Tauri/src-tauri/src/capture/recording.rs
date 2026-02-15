use serde::{Deserialize, Serialize};
use crate::capture::config::{RecordingConfig, RecordingTarget};
use crate::error::CaptureError;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "lowercase")]
pub enum RecordingSessionState {
    Idle,
    Selecting,
    Starting,
    Recording { elapsed_seconds: f64 },
    Stopping,
    Completed,
    Failed { message: String },
    Cancelled,
}

/// Start a screen recording session
pub async fn start_recording(
    _target: RecordingTarget,
    _config: RecordingConfig,
) -> Result<(), CaptureError> {
    // TODO: Implement via ScreenCaptureKit SCRecordingOutput
    // 1. Create SCContentFilter for target
    // 2. Configure SCStreamConfiguration
    // 3. Create SCRecordingOutput with temp file URL
    // 4. Start SCStream
    // 5. Emit recording:state-changed events
    Err(CaptureError::RecordingFailed("Not yet implemented".into()))
}

/// Stop the current recording
pub async fn stop_recording() -> Result<String, CaptureError> {
    // TODO: Stop SCStream, wait for finish, validate output, rename from partial
    Err(CaptureError::RecordingNotActive)
}

/// Cancel the current recording
pub async fn cancel_recording() -> Result<(), CaptureError> {
    // TODO: Cancel SCStream, delete partial file
    Err(CaptureError::RecordingNotActive)
}

/// Get current recording state
pub fn get_state() -> RecordingSessionState {
    RecordingSessionState::Idle
}
