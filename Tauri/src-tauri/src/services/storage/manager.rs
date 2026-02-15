use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::Utc;
use crate::error::CaptureError;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CaptureType {
    Screenshot,
    Recording,
    Gif,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureItem {
    pub id: String,
    pub capture_type: CaptureType,
    pub filename: String,
    pub created_at: String,
    pub is_favorite: bool,
}

impl CaptureItem {
    pub fn new_screenshot(filename: String) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            capture_type: CaptureType::Screenshot,
            filename,
            created_at: Utc::now().to_rfc3339(),
            is_favorite: false,
        }
    }

    pub fn new_recording(filename: String) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            capture_type: CaptureType::Recording,
            filename,
            created_at: Utc::now().to_rfc3339(),
            is_favorite: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureHistory {
    pub items: Vec<CaptureItem>,
}

impl CaptureHistory {
    pub fn new() -> Self {
        Self { items: vec![] }
    }

    pub fn add(&mut self, item: CaptureItem) {
        self.items.push(item);
    }

    pub fn remove(&mut self, id: &str) -> bool {
        let len_before = self.items.len();
        self.items.retain(|i| i.id != id);
        self.items.len() < len_before
    }

    pub fn toggle_favorite(&mut self, id: &str) -> bool {
        if let Some(item) = self.items.iter_mut().find(|i| i.id == id) {
            item.is_favorite = !item.is_favorite;
            true
        } else {
            false
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum StorageLocation {
    Default,
    Desktop,
    Custom { path: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageInfo {
    pub location: StorageLocation,
    pub path: String,
    pub total_items: usize,
    pub total_size_bytes: u64,
}

pub struct StorageManager {
    pub history: CaptureHistory,
    pub location: StorageLocation,
}

impl StorageManager {
    pub fn new() -> Self {
        Self::load()
    }

    /// Load history and settings from disk, falling back to defaults
    pub fn load() -> Self {
        let data_dir = Self::data_dir();

        let history = std::fs::read_to_string(data_dir.join("history.json"))
            .ok()
            .and_then(|data| serde_json::from_str(&data).ok())
            .unwrap_or_else(CaptureHistory::new);

        let location = std::fs::read_to_string(data_dir.join("settings.json"))
            .ok()
            .and_then(|data| serde_json::from_str(&data).ok())
            .unwrap_or(StorageLocation::Default);

        Self { history, location }
    }

    pub fn save_history(&self) -> Result<(), CaptureError> {
        let data_dir = Self::data_dir();
        std::fs::create_dir_all(&data_dir)?;
        let json = serde_json::to_string_pretty(&self.history)?;
        std::fs::write(data_dir.join("history.json"), json)?;
        Ok(())
    }

    pub fn save_settings(&self) -> Result<(), CaptureError> {
        let data_dir = Self::data_dir();
        std::fs::create_dir_all(&data_dir)?;
        let json = serde_json::to_string_pretty(&self.location)?;
        std::fs::write(data_dir.join("settings.json"), json)?;
        Ok(())
    }

    pub fn compute_storage_info(&self) -> StorageInfo {
        let dir = self.screenshots_dir();
        let (total_items, total_size_bytes) = if dir.exists() {
            std::fs::read_dir(&dir)
                .map(|entries| {
                    entries.filter_map(|e| e.ok()).fold((0usize, 0u64), |(c, s), entry| {
                        (c + 1, s + entry.metadata().map(|m| m.len()).unwrap_or(0))
                    })
                })
                .unwrap_or((0, 0))
        } else {
            (0, 0)
        };

        StorageInfo {
            location: self.location.clone(),
            path: dir.to_string_lossy().to_string(),
            total_items,
            total_size_bytes,
        }
    }

    fn data_dir() -> std::path::PathBuf {
        dirs::data_dir()
            .unwrap_or_else(|| std::path::PathBuf::from("/tmp"))
            .join("ScreenCapture")
    }

    pub fn screenshots_dir(&self) -> std::path::PathBuf {
        match &self.location {
            StorageLocation::Default => {
                Self::data_dir().join("Screenshots")
            }
            StorageLocation::Desktop => {
                dirs::desktop_dir().unwrap_or_default()
            }
            StorageLocation::Custom { path } => {
                std::path::PathBuf::from(path)
            }
        }
    }

    pub fn generate_filename(&self, capture_type: &CaptureType, extension: &str) -> String {
        let now = chrono::Local::now();
        let prefix = match capture_type {
            CaptureType::Screenshot => "Screenshot",
            CaptureType::Recording => "Recording",
            CaptureType::Gif => "GIF",
        };
        format!("{} {}.{}", prefix, now.format("%Y-%m-%d at %H.%M.%S"), extension)
    }
}
