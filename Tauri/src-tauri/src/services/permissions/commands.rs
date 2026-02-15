use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PermissionStatus {
    Authorized,
    Denied,
    Restricted,
    NotDetermined,
}

#[tauri::command]
pub fn check_screen_recording_permission() -> PermissionStatus {
    // TODO: CGPreflightScreenCaptureAccess() on macOS 13+
    PermissionStatus::NotDetermined
}

#[tauri::command]
pub fn check_microphone_permission() -> PermissionStatus {
    // TODO: AVCaptureDevice.authorizationStatus(for: .audio)
    PermissionStatus::NotDetermined
}
