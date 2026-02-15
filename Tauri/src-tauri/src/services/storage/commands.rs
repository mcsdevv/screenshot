use crate::services::storage::manager::*;
use crate::error::CaptureError;

#[tauri::command]
pub fn get_history() -> CaptureHistory {
    // TODO: Load from disk
    CaptureHistory::new()
}

#[tauri::command]
pub fn delete_capture(_id: String) -> Result<bool, CaptureError> {
    // TODO: Delete file and remove from history
    Ok(false)
}

#[tauri::command]
pub fn toggle_favorite(_id: String) -> Result<(), CaptureError> {
    // TODO: Toggle favorite in history
    Ok(())
}

#[tauri::command]
pub fn get_storage_info() -> StorageInfo {
    let manager = StorageManager::new();
    StorageInfo {
        location: manager.location.clone(),
        path: manager.screenshots_dir().to_string_lossy().to_string(),
        total_items: 0,
        total_size_bytes: 0,
    }
}

#[tauri::command]
pub fn set_storage_location(_location: StorageLocation) -> Result<(), CaptureError> {
    // TODO: Update storage location, verify permissions
    Ok(())
}
