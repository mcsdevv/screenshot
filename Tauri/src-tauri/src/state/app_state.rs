use std::sync::Mutex;
use crate::services::storage::manager::StorageManager;
use crate::capture::recording::RecordingSessionState;

/// Global application state managed by Tauri
pub struct AppState {
    pub storage: Mutex<StorageManager>,
    pub recording_state: Mutex<RecordingSessionState>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            storage: Mutex::new(StorageManager::new()),
            recording_state: Mutex::new(RecordingSessionState::Idle),
        }
    }
}
