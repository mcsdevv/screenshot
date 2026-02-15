use serde::{Deserialize, Serialize};
use crate::capture::config::{RecordingConfig, RecordingTarget};
use crate::error::CaptureError;
use crate::state::app_state::AppState;
use crate::services::storage::manager::CaptureItem;

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
    state: &tauri::State<'_, AppState>,
) -> Result<(), CaptureError> {
    // Check if already recording
    {
        let rs = state.recording_state.lock().unwrap();
        if matches!(*rs, RecordingSessionState::Recording { .. } | RecordingSessionState::Starting) {
            return Err(CaptureError::RecordingFailed("Recording already in progress".into()));
        }
    }

    // For now, recording is not implemented via ScreenCaptureKit Swift bridge.
    // This returns an informative error rather than crashing.
    Err(CaptureError::RecordingFailed(
        "Screen recording requires ScreenCaptureKit Swift bridge (not yet integrated)".into()
    ))
}

/// Stop the current recording
pub async fn stop_recording(
    state: &tauri::State<'_, AppState>,
) -> Result<CaptureItem, CaptureError> {
    let rs = state.recording_state.lock().unwrap();
    if !matches!(*rs, RecordingSessionState::Recording { .. }) {
        return Err(CaptureError::RecordingNotActive);
    }
    drop(rs);

    // Will be implemented with Swift bridge
    Err(CaptureError::RecordingFailed(
        "Screen recording stop requires ScreenCaptureKit Swift bridge (not yet integrated)".into()
    ))
}

/// Cancel the current recording
pub async fn cancel_recording(
    state: &tauri::State<'_, AppState>,
) -> Result<(), CaptureError> {
    let mut rs = state.recording_state.lock().unwrap();
    if !matches!(*rs, RecordingSessionState::Recording { .. }) {
        return Err(CaptureError::RecordingNotActive);
    }
    *rs = RecordingSessionState::Cancelled;
    Ok(())
}

/// Get current recording state
pub fn get_state(state: &tauri::State<'_, AppState>) -> RecordingSessionState {
    state.recording_state.lock().unwrap().clone()
}
