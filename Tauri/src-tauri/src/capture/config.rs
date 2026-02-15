use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum QualityPreset {
    Low,    // 720p, 5 Mbps
    Medium, // 1080p, 8 Mbps
    High,   // Native, 12 Mbps
}

impl QualityPreset {
    pub fn max_height(&self) -> u32 {
        match self {
            QualityPreset::Low => 720,
            QualityPreset::Medium => 1080,
            QualityPreset::High => u32::MAX,
        }
    }

    pub fn bitrate(&self) -> u32 {
        match self {
            QualityPreset::Low => 5_000_000,
            QualityPreset::Medium => 8_000_000,
            QualityPreset::High => 12_000_000,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ImageFormat {
    Png,
    Jpeg { quality: f32 },
    Tiff,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum RecordingTarget {
    Fullscreen { display_id: Option<u32> },
    Area { x: f64, y: f64, width: f64, height: f64, display_id: u32 },
    Window { window_id: u32 },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingConfig {
    pub quality: QualityPreset,
    pub fps: u32,
    pub include_cursor: bool,
    pub show_mouse_clicks: bool,
    pub include_microphone: bool,
    pub include_system_audio: bool,
    pub exclude_app_audio: bool,
}

impl Default for RecordingConfig {
    fn default() -> Self {
        Self {
            quality: QualityPreset::High,
            fps: 60,
            include_cursor: true,
            show_mouse_clicks: true,
            include_microphone: false,
            include_system_audio: true,
            exclude_app_audio: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayInfo {
    pub id: u32,
    pub width: u32,
    pub height: u32,
    pub scale_factor: f64,
    pub is_primary: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowInfo {
    pub id: u32,
    pub title: String,
    pub app_name: String,
    pub width: u32,
    pub height: u32,
}
