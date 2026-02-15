use crate::services::storage::manager::*;
use crate::state::app_state::AppState;
use crate::error::CaptureError;

#[tauri::command]
pub fn get_history(state: tauri::State<'_, AppState>) -> CaptureHistory {
    state.storage.lock().unwrap().history.clone()
}

#[tauri::command]
pub fn delete_capture(id: String, state: tauri::State<'_, AppState>) -> Result<bool, CaptureError> {
    let mut storage = state.storage.lock().unwrap();
    let filename = storage.history.items.iter()
        .find(|i| i.id == id)
        .map(|i| i.filename.clone());

    if let Some(filename) = &filename {
        let path = storage.screenshots_dir().join(filename);
        let _ = std::fs::remove_file(&path);
    }

    let removed = storage.history.remove(&id);
    if removed {
        storage.save_history()?;
    }
    Ok(removed)
}

#[tauri::command]
pub fn toggle_favorite(id: String, state: tauri::State<'_, AppState>) -> Result<(), CaptureError> {
    let mut storage = state.storage.lock().unwrap();
    storage.history.toggle_favorite(&id);
    storage.save_history()?;
    Ok(())
}

#[tauri::command]
pub fn get_storage_info(state: tauri::State<'_, AppState>) -> StorageInfo {
    state.storage.lock().unwrap().compute_storage_info()
}

#[tauri::command]
pub fn set_storage_location(location: StorageLocation, state: tauri::State<'_, AppState>) -> Result<(), CaptureError> {
    let mut storage = state.storage.lock().unwrap();
    let new_dir = match &location {
        StorageLocation::Custom { path } => std::path::PathBuf::from(path),
        StorageLocation::Desktop => dirs::desktop_dir().unwrap_or_default(),
        StorageLocation::Default => {
            dirs::data_dir()
                .unwrap_or_else(|| std::path::PathBuf::from("/tmp"))
                .join("ScreenCapture")
                .join("Screenshots")
        }
    };
    std::fs::create_dir_all(&new_dir)?;
    storage.location = location;
    storage.save_settings()?;
    Ok(())
}
