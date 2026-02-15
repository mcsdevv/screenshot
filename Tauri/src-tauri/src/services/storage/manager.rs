use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::Utc;

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
        Self {
            history: CaptureHistory::new(),
            location: StorageLocation::Default,
        }
    }

    /// Get the screenshots directory path
    pub fn screenshots_dir(&self) -> std::path::PathBuf {
        match &self.location {
            StorageLocation::Default => {
                let mut path = dirs::data_dir().unwrap_or_default();
                path.push("ScreenCapture");
                path.push("Screenshots");
                path
            }
            StorageLocation::Desktop => {
                dirs::desktop_dir().unwrap_or_default()
            }
            StorageLocation::Custom { path } => {
                std::path::PathBuf::from(path)
            }
        }
    }

    /// Generate a filename for a new capture
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
